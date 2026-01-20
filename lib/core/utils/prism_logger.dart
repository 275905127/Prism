// lib/core/utils/prism_logger.dart
import 'app_log.dart';

/// 抽象日志接口：Engine/Repo 只依赖它，不依赖 AppLog（UI 实现）
///
/// 设计目标：
/// - 解耦：核心层不再 import app_log.dart
/// - 可替换：未来可输出到文件/控制台/关闭日志/release noop
abstract class PrismLogger {
  void log(String line);

  /// Debug 日志（可选）：用于高频打点的收敛（如 Pixiv REQ/RESP）
  /// 默认与 log 等价，由实现类自行决定是否输出。
  void debug(String line) => log(line);
}

/// 默认实现：写入 AppLog（供日志页读取）
///
/// 支持：
/// - 全局开关（enabled）
/// - Debug 开关（debugEnabled）
///
/// 注意：开关值由 UI（LogPage）从 SharedPreferences 读取并写回。
class AppLogLogger implements PrismLogger {
  const AppLogLogger();

  /// 全局日志总开关（静音）
  static bool enabled = true;

  /// Debug 高频日志开关（默认关闭，避免刷屏）
  static bool debugEnabled = false;

  /// 统一设置（便于 UI 一次性更新）
  static void configure({
    bool? enabled,
    bool? debugEnabled,
  }) {
    if (enabled != null) AppLogLogger.enabled = enabled;
    if (debugEnabled != null) AppLogLogger.debugEnabled = debugEnabled;
  }

  @override
  void log(String line) {
    if (!enabled) return;
    AppLog.I.add(line);
  }

  @override
  void debug(String line) {
    if (!enabled) return;
    if (!debugEnabled) return;
    AppLog.I.add(line);
  }
}

/// 空实现：用于关闭日志（可选）
///
/// 仍然保留 debug，以便调用方无需判断
class NoopLogger implements PrismLogger {
  const NoopLogger();

  @override
  void log(String line) {}

  @override
  void debug(String line) {}
}