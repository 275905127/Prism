// lib/core/pixiv/pixiv_repository.dart
import 'dart:async';

import 'package:dio/dio.dart';

import '../models/uni_wallpaper.dart';
import '../utils/prism_logger.dart';
import 'pixiv_client.dart';

/// Pixiv 专用仓库（不走 RuleEngine）
///
/// UI 只需要：
/// - if (_pixivRepo.supports(rule)) => _pixivRepo.fetch(...)
/// - 图片加载用：_pixivRepo.buildImageHeaders()
///
/// 说明：
/// - 搜索接口给的是缩略图 url（square1200）
/// - 详情/下载要拿 /ajax/illust/{id}/pages 才有 regular/original
/// - i.pximg.net 图片一般需要 Referer: https://www.pixiv.net/
///
/// ✅ 支持注入 Dio（由 WallpaperService 统一管理网络策略）
/// ✅ 支持注入 Logger（不再直接依赖 AppLog）
class PixivRepository {
  PixivRepository({
    String? cookie,
    PixivClient? client,

    /// ✅ 注入：用于统一出口（建议传“Pixiv 专用 Dio”，并共享拦截器/代理配置）
    Dio? dio,

    /// ✅ 注入：统一日志出口
    PrismLogger? logger,
  })  : _client = client ?? PixivClient(dio: dio, cookie: cookie),
        _logger = logger;

  final PixivClient _client;
  final PrismLogger? _logger;

  static const String kRuleId = 'pixiv_search_ajax';

  bool supports(dynamic rule) {
    try {
      final id = (rule as dynamic).id?.toString() ?? '';
      if (id == kRuleId) return true;
      if (id.startsWith('pixiv')) return true;
    } catch (_) {}
    return false;
  }

  /// （可选）外部更新 Cookie
  void setCookie(String? cookie) => _client.setCookie(cookie);

  /// 给 CachedNetworkImage / Dio 下载图片用
  Map<String, String> buildImageHeaders() => _client.buildImageHeaders();

  /// Pixiv：
  /// - 首页没关键词没意义（会空）
  /// - 搜索页：query 必填
  Future<List<UniWallpaper>> fetch(
    dynamic rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams, // 预留
  }) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) return const [];

    // 1) 先搜（快速拿到缩略图 + id）
    _logger?.log('REQ pixiv_search_ajax q="$q" page=$page');
    final briefs = await _client.searchArtworks(word: q, page: page);
    _logger?.log('RESP pixiv_search_ajax count=${briefs.length}');

    if (briefs.isEmpty) return const [];

    // 2) 并发补全 pages（拿 regular/original），避免全是缩略图
    final enriched = await _enrichWithPages(
      briefs,
      concurrency: 4,
      timeoutPerItem: const Duration(seconds: 8),
    );

    // 3) 转 UniWallpaper
    final out = <UniWallpaper>[];
    for (final e in enriched) {
      if (e.id.isEmpty) continue;

      // ✅ 详情与下载统一用 original（最高清）
      // 兜底：original 失败则用 regular，再兜底 thumb（保证至少能显示）
      final best = e.originalUrl.isNotEmpty
          ? e.originalUrl
          : (e.regularUrl.isNotEmpty ? e.regularUrl : e.thumbUrl);

      out.add(
        UniWallpaper(
          id: e.id,
          sourceId: 'pixiv',
          thumbUrl: e.thumbUrl,
          fullUrl: best,
          width: e.width.toDouble(),
          height: e.height.toDouble(),
          grade: e.grade,
        ),
      );
    }
    return out;
  }

  Future<List<_PixivEnriched>> _enrichWithPages(
    List<PixivIllustBrief> briefs, {
    int concurrency = 4,
    Duration timeoutPerItem = const Duration(seconds: 8),
  }) async {
    if (briefs.isEmpty) return const [];
    if (concurrency < 1) concurrency = 1;

    // ✅ 关键修复：
    // 以前用 results.length = briefs.length 会产生 null 槽位（并发失败时未赋值 -> 运行期 type cast 崩溃）
    // 这里显式用 nullable 容器承接，再在末尾收口为非空 List<_PixivEnriched>
    final List<_PixivEnriched?> results =
        List<_PixivEnriched?>.filled(briefs.length, null, growable: false);

    // ✅ 线程安全的“任务游标”
    var nextIndex = 0;
    int takeIndex() {
      final v = nextIndex;
      nextIndex++;
      return v;
    }

    Future<void> worker() async {
      while (true) {
        final idx = takeIndex();
        if (idx >= briefs.length) return;

        final b = briefs[idx];

        // 默认：先兜底（thumb 推导 original 仅作 fallback，不保证可用）
        String regular = '';
        String original = _deriveOriginalFromThumb(b.thumbUrl) ?? '';
        final grade = _gradeFromRestrict(b.xRestrict);

        try {
          final pages = await _client.getIllustPages(b.id).timeout(timeoutPerItem);

          if (pages.isNotEmpty) {
            final p0 = pages.first;
            final r = p0.regular.trim();
            final o = p0.original.trim();

            if (r.isNotEmpty) regular = r;
            if (o.isNotEmpty) original = o;
          }
        } catch (e) {
          // 不要炸主流程：能显示 thumb 就够了
          _logger?.log('pixiv pages fail id=${b.id} err=$e');
        } finally {
          // ✅ 无论 pages 成功/失败/超时，都必须写入一个 Enriched，杜绝 null 槽位
          results[idx] = _PixivEnriched(
            id: b.id,
            thumbUrl: b.thumbUrl,
            regularUrl: regular,
            originalUrl: original,
            width: b.width,
            height: b.height,
            grade: grade,
          );
        }
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);

    // ✅ 收口：把 nullable results 转为非空 List<_PixivEnriched>，并过滤空/异常占位
    final out = <_PixivEnriched>[];
    for (final e in results) {
      if (e == null) continue;
      if (e.id.isEmpty) continue;
      out.add(e);
    }
    return out;
  }

  String? _gradeFromRestrict(int xRestrict) {
    if (xRestrict <= 0) return null;
    // 粗暴但可用：>0 即敏感分级
    return xRestrict >= 2 ? 'nsfw' : 'sketchy';
  }

  String? _deriveOriginalFromThumb(String thumb) {
    if (thumb.isEmpty) return null;

    // thumb:
    // https://i.pximg.net/c/250x250_80_a2/img-master/img/2026/01/19/18/48/32/140131153_p0_square1200.jpg
    try {
      final u = Uri.parse(thumb);
      if (!u.host.contains('i.pximg.net')) return null;

      final p = u.path;
      final idx = p.indexOf('/img-master/img/');
      if (idx < 0) return null;

      final tail = p.substring(idx + '/img-master/'.length); // img/2026/...
      var newPath = '/img-original/$tail';

      newPath = newPath
          .replaceAll('_square1200', '')
          .replaceAll('_master1200', '')
          .replaceAll('_custom1200', '');

      // 不强改扩展名（png/jpg 不确定）
      return u.replace(path: newPath, query: '').toString();
    } catch (_) {
      return null;
    }
  }
}

class _PixivEnriched {
  final String id;
  final String thumbUrl;

  /// Pixiv pages 接口给的 regular（推荐用于详情展示的备选）
  final String regularUrl;

  /// Pixiv pages 接口给的 original（用于详情/下载）
  final String originalUrl;

  final int width;
  final int height;
  final String? grade;

  const _PixivEnriched({
    required this.id,
    required this.thumbUrl,
    required this.regularUrl,
    required this.originalUrl,
    required this.width,
    required this.height,
    required this.grade,
  });
}