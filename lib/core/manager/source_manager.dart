// lib/core/manager/source_manager.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/source_rule.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';

// 新增：pack 模型（确保路径与你项目一致）
import '../plugin/pack_models.dart';

/// SourceManager manages the rule list and currently active rule.
///
/// Constraints:
/// - MUST NOT depend on SharedPreferences directly (use [PreferencesStore]).
///
/// Compatibility strategy:
/// - Keep legacy rule APIs for existing UI (rules/activeRule/addRule/setActive/deleteRule/updateRuleHeader).
/// - Add pack installation + activeSource without breaking legacy behavior.
class SourceManager extends ChangeNotifier {
  // ===== Legacy keys (keep) =====
  static const String _kRulesKey = 'prism_rules_v2';
  static const String _kActiveKey = 'prism_active_id_v2';

  // ===== New keys for modular engines/packs =====
  static const String _kPacksKey = 'prism_packs_v1';
  static const String _kActiveSourceKey = 'prism_active_source_v1';

  final PreferencesStore _prefs;
  final PrismLogger _logger;

  // ===== Legacy state =====
  List<SourceRule> _rules = [];
  SourceRule? _activeRule;

  List<SourceRule> get rules => _rules;
  SourceRule? get activeRule => _activeRule;

  // ===== New state: Installed packs + active source =====
  List<InstalledPack> _packs = [];
  ActiveSource _activeSource = const NoneSource();

  List<InstalledPack> get installedPacks => _packs;
  ActiveSource get activeSource => _activeSource;

  InstalledPack? get activePack {
    final s = _activeSource;
    if (s is! PackSource) return null;
    final id = s.packId;
    for (final p in _packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  SourceManager({
    required PreferencesStore prefs,
    required PrismLogger logger,
  })  : _prefs = prefs,
        _logger = logger {
    _load();
  }

  Future<void> _load() async {
    try {
      // ===== 1) Load legacy rules =====
      final list = await _prefs.getStringList(_kRulesKey) ?? const <String>[];

      final parsed = <SourceRule>[];
      for (final raw in list) {
        try {
          final m = jsonDecode(raw);
          if (m is Map<String, dynamic>) {
            parsed.add(SourceRule.fromJson(m));
          }
        } catch (e) {
          _logger.log('SourceManager: skip invalid rule item: $e');
        }
      }
      _rules = parsed;

      final activeId = await _prefs.getString(_kActiveKey);
      if (activeId != null) {
        _activeRule = _rules.where((r) => r.id == activeId).cast<SourceRule?>().firstOrNull;
      }
      _activeRule ??= _rules.isNotEmpty ? _rules.first : null;

      // ===== 2) Load packs =====
      final packsRaw = await _prefs.getStringList(_kPacksKey) ?? const <String>[];
      final packs = <InstalledPack>[];
      for (final raw in packsRaw) {
        try {
          final m = jsonDecode(raw);
          if (m is Map<String, dynamic>) {
            packs.add(InstalledPack.fromJson(m));
          }
        } catch (e) {
          _logger.log('SourceManager: skip invalid pack item: $e');
        }
      }
      _packs = packs;

      // ===== 3) Load activeSource (new). If not exist, derive from legacy active rule. =====
      final activeSourceStr = await _prefs.getString(_kActiveSourceKey);
      if (activeSourceStr != null && activeSourceStr.trim().isNotEmpty) {
        try {
          final m = jsonDecode(activeSourceStr);
          if (m is Map<String, dynamic>) {
            _activeSource = ActiveSource.fromJson(m);
          } else {
            _activeSource = const NoneSource();
          }
        } catch (e) {
          _logger.log('SourceManager: invalid activeSource json: $e');
          _activeSource = const NoneSource();
        }
      } else {
        // Fallback: keep legacy behavior (active rule) as the active source.
        if (_activeRule != null) {
          _activeSource = RuleSource(_activeRule!.id);
        } else {
          _activeSource = const NoneSource();
        }
      }

      // ===== 4) Optional: keep legacy rule selection consistent when activeSource points to rule =====
      final s = _activeSource;
      if (s is RuleSource) {
        final target = _rules.where((r) => r.id == s.ruleId).cast<SourceRule?>().firstOrNull;
        if (target != null) _activeRule = target;
      }

      notifyListeners();
    } catch (e) {
      _logger.log('SourceManager: load failed: $e');
      _rules = [];
      _activeRule = null;
      _packs = [];
      _activeSource = const NoneSource();
      notifyListeners();
    }
  }

  // =========================
  // Legacy API (keep unchanged)
  // =========================

  Future<void> addRule(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Root is not a JSON object');
      }
      final newRule = SourceRule.fromJson(decoded);

      _rules.removeWhere((r) => r.id == newRule.id);
      _rules.add(newRule);
      _activeRule = newRule;

      // keep activeSource in sync with legacy selection
      _activeSource = RuleSource(newRule.id);

      await _save();
      notifyListeners();
    } catch (e) {
      throw Exception('规则格式错误: $e');
    }
  }

  void setActive(String id) {
    if (_rules.isEmpty) return;

    final target = _rules.firstWhere(
      (r) => r.id == id,
      orElse: () => _rules.first,
    );
    _activeRule = target;

    // keep activeSource in sync
    _activeSource = RuleSource(target.id);

    _save(); // best-effort
    notifyListeners();
  }

  void deleteRule(String id) {
    _rules.removeWhere((r) => r.id == id);

    if (_activeRule?.id == id) {
      _activeRule = _rules.isNotEmpty ? _rules.first : null;
    }

    // If deleting current rule and activeSource is rule, update it too.
    final s = _activeSource;
    if (s is RuleSource && s.ruleId == id) {
      _activeSource = _activeRule != null ? RuleSource(_activeRule!.id) : const NoneSource();
    }

    _save(); // best-effort
    notifyListeners();
  }

  Future<void> updateRuleHeaders(String ruleId, Map<String, String>? headers) async {
    if (_rules.isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final m = Map<String, dynamic>.from(old.toJson());
    m['headers'] = headers;

    final updated = SourceRule.fromJson(m);

    _rules[idx] = updated;
    if (_activeRule?.id == ruleId) {
      _activeRule = updated;
    }

    await _save();
    notifyListeners();
  }

  Future<void> updateRuleHeader(String ruleId, String key, String? value) async {
    if (key.trim().isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final h = <String, String>{...?(old.headers)};

    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      h.remove(key);
      if (key.toLowerCase() == 'cookie') {
        h.remove('cookie');
        h.remove('Cookie');
      }
    } else {
      h[key] = v;
    }

    await updateRuleHeaders(ruleId, h.isEmpty ? null : h);
  }

  // =========================
  // New API: packs / engine modules
  // =========================

  /// Upsert an installed pack record.
  /// Note: this does NOT execute the engine; only stores metadata/installation info.
  Future<void> upsertPack(InstalledPack pack) async {
    _packs.removeWhere((p) => p.id == pack.id);
    _packs.add(pack);

    // If active source points to this pack but it was previously missing, keep it.
    await _save();
    notifyListeners();
  }

  Future<void> removePack(String packId) async {
    _packs.removeWhere((p) => p.id == packId);

    final s = _activeSource;
    if (s is PackSource && s.packId == packId) {
      // fallback to legacy active rule
      _activeSource = _activeRule != null ? RuleSource(_activeRule!.id) : const NoneSource();
    }

    await _save();
    notifyListeners();
  }

  /// Switch active source to a pack engine module.
  /// Legacy UI still reads [activeRule], so this won't break it,
  /// but pack-based pages will start using [activeSource] later.
  Future<void> setActivePack(String packId) async {
    _activeSource = PackSource(packId);
    await _save();
    notifyListeners();
  }

  /// Enable/disable a pack (metadata-only).
  Future<void> setPackEnabled(String packId, bool enabled) async {
    final idx = _packs.indexWhere((p) => p.id == packId);
    if (idx < 0) return;

    final old = _packs[idx];
    _packs[idx] = InstalledPack(
      manifest: old.manifest,
      installedAtMs: old.installedAtMs,
      localPath: old.localPath,
      enabled: enabled,
    );

    await _save();
    notifyListeners();
  }

  // =========================
  // Save (legacy + new)
  // =========================

  Future<void> _save() async {
    try {
      // legacy save
      final jsonList = _rules.map((r) => jsonEncode(r.toJson())).toList(growable: false);
      await _prefs.setStringList(_kRulesKey, jsonList);

      if (_activeRule != null) {
        await _prefs.setString(_kActiveKey, _activeRule!.id);
      } else {
        await _prefs.remove(_kActiveKey);
      }

      // new save: packs
      final packList = _packs
          .map((p) => jsonEncode(p.toJson()))
          .toList(growable: false);
      await _prefs.setStringList(_kPacksKey, packList);

      // new save: activeSource
      await _prefs.setString(_kActiveSourceKey, jsonEncode(_activeSource.toJson()));
    } catch (e) {
      _logger.log('SourceManager: save failed: $e');
    }
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}