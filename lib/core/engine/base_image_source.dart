// lib/core/engine/base_image_source.dart
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../storage/preferences_store.dart';

/// 图源引擎统一接口
/// 实现了多态：RuleEngine (通用) 和 PixivRepository (专用) 都将实现此接口
abstract class BaseImageSource {
  /// 该引擎是否支持当前规则
  bool supports(SourceRule rule);

  /// 恢复会话/上下文 (Hydration)
  /// 例如：读取 Cookie、同步配置、设置 Headers
  Future<void> restoreSession({
    required PreferencesStore prefs,
    required SourceRule rule,
  });

  /// 统一获取数据
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  });

  /// 检查登录状态 (默认返回 true，需要鉴权的引擎覆盖此方法)
  Future<bool> checkLoginStatus(SourceRule rule) async => true;
}
