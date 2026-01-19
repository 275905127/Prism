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

  bool get hasCookie => _client.hasCookie;

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
    Map<String, dynamic>? filterParams,
  }) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) return const [];

    // ---------- 读取 filters（UI -> Service -> Repo） ----------
    String order = 'date_d';
    String mode = 'all';
    String sMode = 's_tag';

    final fp = filterParams ?? const <String, dynamic>{};

    String _pickStr(String k, String fallback) {
      final v = fp[k];
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? fallback : s;
    }

    order = _pickStr('order', order);
    mode = _pickStr('mode', mode);
    sMode = _pickStr('s_mode', sMode);

    // ---------- 两档体验：无 Cookie 时限制某些选项 ----------
    // 1) 热门排序通常需要登录（或会返回空/降级），这里直接降级到最新
    if (!hasCookie && order.toLowerCase().contains('popular')) {
      _logger?.log('pixiv filter blocked (no cookie): order=$order -> date_d');
      order = 'date_d';
    }

    // 2) R-18：无 Cookie 时直接降级为 safe（避免“看似可选但实际加载失败/空”）
    if (!hasCookie && mode.toLowerCase() == 'r18') {
      _logger?.log('pixiv filter blocked (no cookie): mode=r18 -> safe');
      mode = 'safe';
    }

    // ---------- 1) 先搜（快速拿到缩略图 + id） ----------
    _logger?.log('REQ pixiv_search_ajax q="$q" page=$page order=$order mode=$mode s_mode=$sMode');
    final briefs = await _client.searchArtworks(
      word: q,
      page: page,
      order: order,
      mode: mode,
      sMode: sMode,
    );
    _logger?.log('RESP pixiv_search_ajax count=${briefs.length}');

    if (briefs.isEmpty) return const [];

    // ---------- 2) 并发补全 pages（拿 regular/original） ----------
    final enriched = await _enrichWithPages(
      briefs,
      concurrency: 4,
      timeoutPerItem: const Duration(seconds: 8),
    );

    // ---------- 3) 转 UniWallpaper（详情与下载用 original） ----------
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

    // ✅ 关键修复：nullable 容器承接并发结果，末尾收口为非空
    final List<_PixivEnriched?> results =
        List<_PixivEnriched?>.filled(briefs.length, null, growable: false);

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
          _logger?.log('pixiv pages fail id=${b.id} err=$e');
        } finally {
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
    return xRestrict >= 2 ? 'nsfw' : 'sketchy';
    }

  String? _deriveOriginalFromThumb(String thumb) {
    if (thumb.isEmpty) return null;

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

      return u.replace(path: newPath, query: '').toString();
    } catch (_) {
      return null;
    }
  }
}

class _PixivEnriched {
  final String id;
  final String thumbUrl;
  final String regularUrl;
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