import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_rule.dart';

class SourceManager extends ChangeNotifier {
  // ✅ 升版本，隔离旧数据（避免以前的坏规则继续加载）
  static const String _kRulesKey = 'prism_rules_v2';
  static const String _kActiveKey = 'prism_active_id_v2';

  List<SourceRule> _rules = [];
  SourceRule? _activeRule;

  List<SourceRule> get rules => _rules;
  SourceRule? get activeRule => _activeRule;

  SourceManager() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final List<String> list = prefs.getStringList(_kRulesKey) ?? [];
    if (list.isNotEmpty) {
      _rules = list.map((e) => SourceRule.fromJson(jsonDecode(e))).toList();
    } else {
      _rules = [];
    }

    final activeId = prefs.getString(_kActiveKey);
    if (activeId != null) {
      _activeRule = _rules.where((r) => r.id == activeId).cast<SourceRule?>().firstOrNull;
    }

    _activeRule ??= _rules.isNotEmpty ? _rules.first : null;

    notifyListeners();
  }

  Future<void> addRule(String jsonString) async {
    try {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      final newRule = SourceRule.fromJson(map);

      _rules.removeWhere((r) => r.id == newRule.id);
      _rules.add(newRule);

      _activeRule = newRule;

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
    _save();
    notifyListeners();
  }

  void deleteRule(String id) {
    _rules.removeWhere((r) => r.id == id);

    if (_activeRule?.id == id) {
      _activeRule = _rules.isNotEmpty ? _rules.first : null;
    }

    _save();
    notifyListeners();
  }

  /// ✅ 更新某条规则的 headers（不可变写法：toJson -> 改 -> fromJson）
  Future<void> updateRuleHeaders(String ruleId, Map<String, String>? headers) async {
    if (_rules.isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final m = Map<String, dynamic>.from(old.toJson());

    // headers 允许为 null（表示清空）
    m['headers'] = headers;

    final updated = SourceRule.fromJson(m);

    _rules[idx] = updated;
    if (_activeRule?.id == ruleId) {
      _activeRule = updated;
    }

    await _save();
    notifyListeners();
  }

  /// ✅ 更新单个 header（如 Cookie），value 为空则移除该 key
  Future<void> updateRuleHeader(String ruleId, String key, String? value) async {
    if (key.trim().isEmpty) return;

    final idx = _rules.indexWhere((r) => r.id == ruleId);
    if (idx < 0) return;

    final old = _rules[idx];
    final h = <String, String>{...?(old.headers)};

    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      h.remove(key);
      // 顺手把大小写变体也清掉，避免重复
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
    final prefs = await SharedPreferences.getInstance();

    final jsonList = _rules.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_kRulesKey, jsonList);

    if (_activeRule != null) {
      await prefs.setString(_kActiveKey, _activeRule!.id);
    } else {
      await prefs.remove(_kActiveKey);
    }
  }
}

// ✅ 不引入额外依赖的 firstOrNull
extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
