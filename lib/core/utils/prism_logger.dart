import 'app_log.dart';

/// 核心层日志接口：
/// - log(): 关键链路（REQ/RESP/ERR/状态变化）
/// - debug(): 高频细节（params/headers/body 截断等），可通过开关关闭
abstract class PrismLogger {
  void log(String line);
  void debug(String line);
}

/// 默认实现：写入 AppLog（供日志页读取）
class AppLogLogger implements PrismLogger {
  const AppLogLogger();

  @override
  void log(String line) => AppLog.I.addInfo(line);

  @override
  void debug(String line) => AppLog.I.addDebug(line);
}

/// 空实现：用于关闭日志（可选）
class NoopLogger implements PrismLogger {
  const NoopLogger();

  @override
  void log(String line) {}

  @override
  void debug(String line) {}
}
