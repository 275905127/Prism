import 'dart:collection';

enum AppLogLevel { info, debug }

class AppLog {
  static final AppLog I = AppLog._();
  AppLog._();

  static const int _max = 400;
  final Queue<String> _lines = Queue<String>();

  bool _enabled = true;
  bool _debugEnabled = false;

  bool get enabled => _enabled;
  bool get debugEnabled => _debugEnabled;

  void setEnabled(bool v) => _enabled = v;
  void setDebugEnabled(bool v) => _debugEnabled = v;

  List<String> get lines => List.unmodifiable(_lines);

  void addInfo(String line) => _add(AppLogLevel.info, line);
  void addDebug(String line) => _add(AppLogLevel.debug, line);

  void _add(AppLogLevel level, String line) {
    if (!_enabled) return;
    if (level == AppLogLevel.debug && !_debugEnabled) return;

    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final prefix = (level == AppLogLevel.debug) ? '[D]' : '[I]';
    _lines.addFirst('[$ts] $prefix $line');

    while (_lines.length > _max) {
      _lines.removeLast();
    }
  }

  void clear() => _lines.clear();
}