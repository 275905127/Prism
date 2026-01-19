// lib/core/utils/prism_logger.dart
import 'app_log.dart';

/// 抽象日志接口：Engine/Repo 只依赖它，不依赖 AppLog（UI 实现）
///
/// 设计目标：
/// - 解耦：核心层不再 import app_log.dart
/// - 可替换：未来可输出到文件/控制台/关闭日志/release noop
abstract class PrismLogger {
  void log(String line);
}

/// 默认实现：写入 AppLog（供日志页读取）
class AppLogLogger implements PrismLogger {
  const AppLogLogger();

  @override
  void log(String line) => AppLog.I.add(line);
}

/// 空实现：用于关闭日志（可选）
class NoopLogger implements PrismLogger {
  const NoopLogger();

  @override
  void log(String line) {}
}