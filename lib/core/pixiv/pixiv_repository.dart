// lib/core/pixiv/pixiv_repository.dart
import 'dart:async';

import 'package:dio/dio.dart';

import '../models/uni_wallpaper.dart';
import '../utils/prism_logger.dart';
import 'pixiv_client.dart';

/// Pixiv 专用仓库
/// ✅ 修复：补回 setCookie 和 copyWith 方法，解决构建报错
/// ✅ 功能：强制同步 Rule 中的 User-Agent 和 Cookie
class PixivRepository {
  PixivRepository({
    String? cookie,
    PixivClient? client,
    Dio? dio,
    PrismLogger? logger,
    PixivPagesConfig? pagesConfig,
  })  : _client = client ?? PixivClient(dio: dio, cookie: cookie),
        _logger = logger,
        _pagesConfig = pagesConfig ?? const PixivPagesConfig();

  final PixivClient _client;
  final PrismLogger? _logger;

  static const String kRuleId = 'pixiv_search_ajax';
  static const String kUserRuleId = 'pixiv_user';

  bool supports(dynamic rule) {
    try {
      final id = (rule as dynamic).id?.toString() ?? '';
      if (id == kRuleId) return true;
      if (id == kUserRuleId) return true;
      if (id.startsWith('pixiv')) return true;
    } catch (_) {}
    return false;
  }

  bool get hasCookie => _client.hasCookie;

  /// 🔥 [修复] 补回此方法，供 WallpaperService 调用
  void setCookie(String? cookie) => _client.setCookie(cookie);

  /// 给 CachedNetworkImage / Dio 下载图片用
  Map<String, String> buildImageHeaders() => _client.buildImageHeaders();

  PixivPagesConfig _pagesConfig;
  PixivPagesConfig get pagesConfig => _pagesConfig;

  void updatePagesConfig(PixivPagesConfig config) {
    _pagesConfig = config;
  }

  // ---------- Config sync ----------

  /// 从 Rule 中提取 Cookie 和 User-Agent 并注入 Client
  void _syncConfigFromRule(dynamic rule) {
    try {
      final dynamic headers = (rule as dynamic).headers;
      if (headers == null || headers is! Map) return;

      // 提取 Cookie
      final dynamic c1 = headers['Cookie'];
      final dynamic c2 = headers['cookie'];
      final cookie = (c1 ?? c2)?.toString().trim();

      // 提取 User-Agent
      final dynamic ua1 = headers['User-Agent'];
      final dynamic ua2 = headers['user-agent'];
      final ua = (ua1 ?? ua2)?.toString().trim();

      // 注入 Client
      if ((cookie != null && cookie.isNotEmpty) || (ua != null && ua.isNotEmpty)) {
        _client.updateConfig(
          cookie: cookie,
          userAgent: ua,
        );
        
        if (ua != null) {
          _logger?.log('pixiv config synced: UA updated');
        }
        if (cookie != null) {
          final prefix = cookie.length <= 12 ? cookie : cookie.substring(0, 12);
          _logger?.log('pixiv config synced: Cookie injected ($prefix...)');
        }
      }
    } catch (e) {
      _logger?.log('pixiv config sync failed: $e');
    }
  }

  /// Fetch 入口
  Future<List<UniWallpaper>> fetch(
    dynamic rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) return const [];

    // 1. 同步配置 (Cookie + UA)
    _syncConfigFromRule(rule);

    // 2. 读取 filters
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

    // 3. 降级逻辑 (无 Cookie 时)
    if (!hasCookie) {
      if (order.toLowerCase().contains('popular')) {
        _logger?.log('pixiv filter blocked (no cookie): order=$order -> date_d');
        order = 'date_d';
      }
      if (mode.toLowerCase() == 'r18') {
        _logger?.log('pixiv filter blocked (no cookie): mode=r18 -> safe');
        mode = 'safe';
      }
    }

    _logger?.log(
      'REQ pixiv q="$q" page=$page order=$order mode=$mode cookie=${hasCookie ? 1 : 0}',
    );

    // 4. 执行搜索
    final ruleId = (rule as dynamic).id?.toString() ?? '';
    List<PixivIllustBrief> briefs = [];

    if (ruleId == kUserRuleId) {
       briefs = await _client.getUserArtworks(userId: q, page: page);
    } else {
       briefs = await _client.searchArtworks(
        word: q,
        page: page,
        order: order,
        mode: mode,
        sMode: sMode,
      );
    }
    
    _logger?.log('RESP pixiv count=${briefs.length}');

    if (briefs.isNotEmpty) {
      final first3 = briefs.take(3).map((e) => e.id).toList();
      _logger?.log('pixiv verify first3=$first3');
    }

    if (briefs.isEmpty) return const [];

    // 5. 并发补全
    final enriched = await _enrichWithPages(
      briefs,
      concurrency: _pagesConfig.concurrency,
      timeoutPerItem: _pagesConfig.timeoutPerItem,
      retryCount: _pagesConfig.retryCount,
      retryDelay: _pagesConfig.retryDelay,
    );

    // 6. 转换结果
    final out = <UniWallpaper>[];
    for (final e in enriched) {
      if (e.id.isEmpty) continue;
      
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
    int retryCount = 1,
    Duration retryDelay = const Duration(milliseconds: 280),
  }) async {
    if (briefs.isEmpty) return const [];
    
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

        if (original.isEmpty) {
          try {
            final pages = await _client.getIllustPages(b.id).timeout(timeoutPerItem);
            if (pages.isNotEmpty) {
              final p0 = pages.first;
              if (p0.regular.isNotEmpty) regular = p0.regular;
              if (p0.original.isNotEmpty) original = p0.original;
            }
          } catch (e) {
            // ignore
          }
        } else {
           regular = original; 
        }

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

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);

    final out = <_PixivEnriched>[];
    for (final e in results) {
      if (e != null && e.id.isNotEmpty) out.add(e);
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

      final tail = p.substring(idx + '/img-master/'.length); 
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

class PixivPagesConfig {
  final int concurrency;
  final Duration timeoutPerItem;
  final int retryCount;
  final Duration retryDelay;

  const PixivPagesConfig({
    this.concurrency = 4,
    this.timeoutPerItem = const Duration(seconds: 8),
    this.retryCount = 1,
    this.retryDelay = const Duration(milliseconds: 280),
  });

  /// 🔥 [修复] 补回此方法，供 WallpaperService 调用
  PixivPagesConfig copyWith({
    int? concurrency,
    Duration? timeoutPerItem,
    int? retryCount,
    Duration? retryDelay,
  }) {
    return PixivPagesConfig(
      concurrency: concurrency ?? this.concurrency,
      timeoutPerItem: timeoutPerItem ?? this.timeoutPerItem,
      retryCount: retryCount ?? this.retryCount,
      retryDelay: retryDelay ?? this.retryDelay,
    );
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
