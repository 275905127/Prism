// lib/core/manager/source_manager.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_rule.dart';

class SourceManager extends ChangeNotifier {
  static const String _kRulesKey = 'prism_rules_v1';
  static const String _kActiveKey = 'prism_active_id';

  List<SourceRule> _rules = [];
  SourceRule? _activeRule;

  List<SourceRule> get rules => _rules;
  SourceRule? get activeRule => _activeRule;

  SourceManager() {
    _load();
  }

  // 1. 加载本地存储
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 读取规则列表
    final List<String> list = prefs.getStringList(_kRulesKey) ?? [];
    if (list.isNotEmpty) {
      _rules = list.map((e) => SourceRule.fromJson(jsonDecode(e))).toList();
    } else {
      // 如果本地没数据，注入测试源
      _injectTestSource(); 
    }

    // 读取上次选中的源
    final activeId = prefs.getString(_kActiveKey);
    if (activeId != null && _rules.any((r) => r.id == activeId)) {
      _activeRule = _rules.firstWhere((r) => r.id == activeId);
    } else if (_rules.isNotEmpty) {
      _activeRule = _rules.first;
    }
    notifyListeners();
  }

  // 2. 导入新规则 (核心功能)
  Future<void> addRule(String jsonString) async {
    try {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      final newRule = SourceRule.fromJson(map);

      // 如果 ID 重复，先删除旧的
      _rules.removeWhere((r) => r.id == newRule.id);
      _rules.add(newRule);
      
      // 自动选中新导入的
      _activeRule = newRule;
      
      await _save();
      notifyListeners();
    } catch (e) {
      throw Exception('规则格式错误: $e');
    }
  }

  // 3. 切换源
  void setActive(String id) {
    final target = _rules.firstWhere((r) => r.id == id, orElse: () => _rules.first);
    _activeRule = target;
    _save();
    notifyListeners();
  }
  
  // 4. 删除源
  void deleteRule(String id) {
    _rules.removeWhere((r) => r.id == id);
    if (_activeRule?.id == id) {
      _activeRule = _rules.isNotEmpty ? _rules.first : null;
    }
    _save();
    notifyListeners();
  }

  // 持久化保存
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // 保存列表
    final jsonList = _rules.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_kRulesKey, jsonList);
    // 保存选中项
    if (_activeRule != null) {
      await prefs.setString(_kActiveKey, _activeRule!.id);
    }
  }

  void _injectTestSource() {
    // 这里放之前的 JsonPlaceholder 测试源
     _rules.add(SourceRule.fromJson({
      "id": "jsonplaceholder",
      "name": "Test Source",
      "base_url": "https://jsonplaceholder.typicode.com",
      "search": {"url": "/photos?_limit=10"},
      "parser": {
        "list_node": "\$[*]",
        "id": "id",
        "thumb": "thumbnailUrl",
        "full": "url",
        "width": "id",
        "height": "albumId"
      }
    }));
    _activeRule = _rules.first;
  }
}