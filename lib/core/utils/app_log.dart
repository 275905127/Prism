import 'dart:collection';

class AppLog {
  static final AppLog I = AppLog._();
  AppLog._();

  static const int _max = 200;
  final Queue<String> _lines = Queue<String>();

  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _lines.addFirst('[$ts] $line');
    while (_lines.length > _max) {
      _lines.removeLast();
    }
  }

  void clear() => _lines.clear();
}