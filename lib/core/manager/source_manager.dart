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