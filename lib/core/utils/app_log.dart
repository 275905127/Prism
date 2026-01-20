// lib/core/utils/app_log.dart
import 'dart:collection';

class AppLog {
  static final AppLog I = AppLog._();
  AppLog._();

  static const int _max = 200;
  final Queue<String> _lines = Queue<String>();

  /// 冻结写入（兜底保护）
  bool _frozen = false;

  List<String> get lines => List.unmodifiable(_lines);

  /// 冻结日志写入（通常由 Logger 层控制，这里是保险）
  void freeze() => _frozen = true;

  /// 恢复日志写入
  void resume() => _frozen = false;

  /// 写入单条日志
  void add(String line) {
    if (_frozen) return;

    final l = line.trim();
    if (l.isEmpty) return;

    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _lines.addFirst('[$ts] $l');

    while (_lines.length > _max) {
      _lines.removeLast();
    }
  }

  /// 批量写入（给 interceptor / debug dump 使用）
  void addAll(Iterable<String> lines) {
    if (_frozen) return;
    for (final l in lines) {
      add(l);
    }
  }

  void clear() => _lines.clear();
}