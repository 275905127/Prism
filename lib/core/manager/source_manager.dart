// lib/core/manager/source_manager.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/source_rule.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';

/// SourceManager manages the rule list and currently active rule.
///
/// Constraints:
/// - MUST NOT depend on SharedPreferences directly (use [PreferencesStore]).
/// - Must be null-safe and resilient to async race conditions.
class SourceManager extends ChangeNotifier {
  static const String _kRulesKey = 'prism_rules_v2';
  static const String _kActiveKey = 'prism_active_id_v2';

  final PreferencesStore _prefs;
  final PrismLogger _logger;

  List<SourceRule> _rules = <SourceRule>[];
  SourceRule? _activeRule;

  List<SourceRule> get rules => List.unmodifiable(_rules);
  SourceRule? get activeRule => _activeRule;

  SourceManager({
    required PreferencesStore prefs,
    required PrismLogger logger,
  })  : _prefs = prefs,
        _logger = logger {
    _load();
  }

  // -------------------- load / save --------------------

  Future<void> _load() async {
    try {
      final list = await _prefs.getStringList(_kRulesKey) ?? const <String>[];

      final parsed = <SourceRule>[];
      for (final raw in list) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            // 兼容 Map<dynamic,dynamic>
            final m = decoded.map((k, v) => MapEntry(k.toString(), v));
            parsed.add(SourceRule.fromJson(Map<String, dynamic>.from(m)));
          }
        } catch (e) {
          _logger.log('SourceManager: skip invalid rule item: $e');
        }
      }

      _rules = parsed;

      final activeId = (await _prefs.getString(_kActiveKey))?.trim();
      if (activeId != null && activeId.isNotEmpty) {
        _activeRule = _rules.firstWhereOrNull((r) => r.id == activeId);
      }

      _activeRule ??= _rules.isNotEmpty ? _rules.first : null;

      notifyListeners();
    } catch (e) {
      _logger.log('SourceManager: load rules failed: $e');
      _rules = <SourceRule>[];
      _activeRule = null;
      notifyListeners();
    }
  }

  /// Save rules and active id.
  /// IMPORTANT: uses snapshots to avoid async race where `_activeRule` changes mid-save.
  Future<void> _save() async {
    // take snapshots to prevent async race conditions
    final rulesSnapshot = List<SourceRule>.from(_rules);
    final activeIdSnapshot = _activeRule?.id;

    try {
      final jsonList = rulesSnapshot.map((r) => jsonEncode(r.toJson())).toList(growable: false);
      await _prefs.setStringList(_kRulesKey, jsonList);

      if (activeIdSnapshot != null && activeIdSnapshot.trim().isNotEmpty) {
        await _prefs.setString(_kActiveKey, activeIdSnapshot);
      } else {
        await _prefs.remove(_kActiveKey);
      }
    } catch (e) {
      _logger.log('SourceManager: save rules failed: $e');
    }
  }

  // -------------------- public mutations --------------------

  Future<void> addRule(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        throw const FormatException('Root is not a JSON object');
      }

      final m = decoded.map((k, v) => MapEntry(k.toString(), v));
      final newRule = SourceRule.fromJson(Map<String, dynamic>.from(m));

      _rules.removeWhere((r) => r.id == newRule.id);
      _rules.add(newRule);
      _activeRule = newRule;

      await _save();
      notifyListeners();
    } catch (e) {
      throw Exception('规则格式错误: $e');
    }
  }

  /// Set active rule.
  /// Best-effort persistence; does not throw.
  void setActive(String id) {
    if (_rules.isEmpty) return;

    final target = _rules.firstWhere(
      (r) => r.id == id,
      orElse: () => _rules.first,
    );

    _activeRule = target;
    // best-effort (do not await)
    _save();
    notifyListeners();
  }

  /// Delete a rule.
  /// Best-effort persistence; does not throw.
  void deleteRule(String id) {
    _rules.removeWhere((r) => r.id == id);

    if (_activeRule?.id == id) {
      _activeRule = _rules.isNotEmpty ? _rules.first : null;
    }

    // best-effort (do not await)
    _save();
    notifyListeners();
  }

  /// Replace whole headers map for a rule.
  /// This is an awaited mutation because callers often expect it to be persisted (e.g., Pixiv cookie save).
  Future<void> updateRuleHeaders(String ruleId, Map<String, String>? headers) async {
    if (_rules.isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];

    // ensure we write a JSON-serializable map (String->String)
    final normalizedHeaders = headers == null
        ? null
        : headers.map((k, v) => MapEntry(k.toString(), v.toString()));

    final m = Map<String, dynamic>.from(old.toJson());
    m['headers'] = normalizedHeaders;

    final updated = SourceRule.fromJson(m);

    _rules[idx] = updated;
    if (_activeRule?.id == ruleId) {
      _activeRule = updated;
    }

    await _save();
    notifyListeners();
  }

  /// Update one header key-value pair.
  /// Null/empty value means remove.
  Future<void> updateRuleHeader(String ruleId, String key, String? value) async {
    final k = key.trim();
    if (k.isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final h = <String, String>{...?(old.headers)};

    final v = (value ?? '').trim();
    if (v.isEmpty) {
      // remove target key and cookie variants if key is cookie
      h.remove(k);
      if (k.toLowerCase() == 'cookie') {
        h.remove('cookie');
        h.remove('Cookie');
      }
    } else {
      h[k] = v;
      // if writing Cookie, normalize both keys? (optional)
      if (k.toLowerCase() == 'cookie') {
        h['Cookie'] = v;
      }
    }

    await updateRuleHeaders(ruleId, h.isEmpty ? null : h);
  }
}

/// Local extensions to avoid relying on new SDK Iterable.firstWhereOrNull availability everywhere.
extension _IterableExt<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}