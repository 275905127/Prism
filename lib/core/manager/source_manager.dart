// lib/core/manager/source_manager.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/source_rule.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';

/// SourceManager manages the rule list and currently active rule.
///
/// Architecture constraints:
/// - MUST NOT depend on SharedPreferences directly (use [PreferencesStore]).
/// - UI should depend on SourceManager state only; persistence happens here.
class SourceManager extends ChangeNotifier {
  // ✅ Versioned keys to isolate legacy/bad rules
  static const String _kRulesKey = 'prism_rules_v2';
  static const String _kActiveKey = 'prism_active_id_v2';

  final PreferencesStore _prefs;
  final PrismLogger _logger;

  List<SourceRule> _rules = [];
  SourceRule? _activeRule;

  List<SourceRule> get rules => _rules;
  SourceRule? get activeRule => _activeRule;

  SourceManager({
    required PreferencesStore prefs,
    required PrismLogger logger,
  })  : _prefs = prefs,
        _logger = logger {
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _prefs.getStringList(_kRulesKey) ?? const <String>[];

      final parsed = <SourceRule>[];
      for (final raw in list) {
        try {
          final m = jsonDecode(raw);
          if (m is Map<String, dynamic>) {
            parsed.add(SourceRule.fromJson(m));
          }
        } catch (e) {
          // Skip broken items, but keep others
          _logger.w('SourceManager', 'Skip invalid rule item: $e');
        }
      }
      _rules = parsed;

      final activeId = await _prefs.getString(_kActiveKey);
      if (activeId != null) {
        _activeRule = _rules.where((r) => r.id == activeId).cast<SourceRule?>().firstOrNull;
      }

      _activeRule ??= _rules.isNotEmpty ? _rules.first : null;
      notifyListeners();
    } catch (e) {
      _logger.e('SourceManager', 'Load rules failed: $e');
      _rules = [];
      _activeRule = null;
      notifyListeners();
    }
  }

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

      await _save();
      notifyListeners();
    } catch (e) {
      // Keep message user-friendly; caller can map further if needed
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
    _save(); // fire-and-forget; persistence is best-effort
    notifyListeners();
  }

  void deleteRule(String id) {
    _rules.removeWhere((r) => r.id == id);

    if (_activeRule?.id == id) {
      _activeRule = _rules.isNotEmpty ? _rules.first : null;
    }

    _save(); // fire-and-forget
    notifyListeners();
  }

  /// ✅ Update a rule's headers using an immutable approach: toJson -> mutate -> fromJson.
  Future<void> updateRuleHeaders(String ruleId, Map<String, String>? headers) async {
    if (_rules.isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final m = Map<String, dynamic>.from(old.toJson());

    // headers may be null (meaning clear)
    m['headers'] = headers;

    final updated = SourceRule.fromJson(m);

    _rules[idx] = updated;
    if (_activeRule?.id == ruleId) {
      _activeRule = updated;
    }

    await _save();
    notifyListeners();
  }

  /// ✅ Update a single header (e.g., Cookie). If [value] is empty, remove the key.
  Future<void> updateRuleHeader(String ruleId, String key, String? value) async {
    if (key.trim().isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final h = <String, String>{...?(old.headers)};

    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      h.remove(key);
      // Clean case variants to avoid duplicates
      if (key.toLowerCase() == 'cookie') {
        h.remove('cookie');
        h.remove('Cookie');
      }
    } else {
      h[key] = v;
    }

    await updateRuleHeaders(ruleId, h.isEmpty ? null : h);
  }

  Future<void> _save() async {
    try {
      final jsonList = _rules.map((r) => jsonEncode(r.toJson())).toList(growable: false);
      await _prefs.setStringList(_kRulesKey, jsonList);

      if (_activeRule != null) {
        await _prefs.setString(_kActiveKey, _activeRule!.id);
      } else {
        await _prefs.remove(_kActiveKey);
      }
    } catch (e) {
      _logger.e('SourceManager', 'Save rules failed: $e');
    }
  }
}

/// ✅ firstOrNull without extra deps
extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}