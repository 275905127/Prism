// lib/core/services/wallpaper_service.dart
import '../engine/rule_engine.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../pixiv/pixiv_repository.dart';

/// 桥梁层：统一管理所有图源引擎的调用
/// UI 只需与此类交互，无需关心底层是 RuleEngine 还是 PixivRepository
class WallpaperService {
  final RuleEngine _standardEngine = RuleEngine();
  final PixivRepository _pixivRepo = PixivRepository();

  /// 核心方法：获取壁纸列表
  /// 内部自动判断使用哪个引擎
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    // 1. 路由逻辑：判断是否为 Pixiv 特殊源
    if (_pixivRepo.supports(rule)) {
      return _fetchFromPixiv(rule, page, query);
    }

    // 2. 默认逻辑：走通用 JSON 引擎
    return _standardEngine.fetch(
      rule,
      page: page,
      query: query,
      filterParams: filterParams,
    );
  }

  /// 辅助逻辑：Pixiv 需要特殊处理 query
  Future<List<UniWallpaper>> _fetchFromPixiv(
    SourceRule rule,
    int page,
    String? query,
  ) async {
    // Pixiv 首页必须有关键词：优先用规则 defaultKeyword，否则兜底
    final String q = (query != null && query.trim().isNotEmpty)
        ? query
        : (rule.defaultKeyword ?? 'illustration').trim();
        
    return _pixivRepo.fetch(
      rule,
      page: page,
      query: q,
    );
  }

  /// UI 获取图片时需要的 Headers (用于 CachedNetworkImage / Dio)
  /// 统一在这里处理，UI 不必写 if-else
  Map<String, String>? getImageHeaders(SourceRule? rule) {
    if (rule == null) return null;

    if (_pixivRepo.supports(rule)) {
      return _pixivRepo.buildImageHeaders();
    }
    
    return rule.buildRequestHeaders();
  }
}
