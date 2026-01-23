// lib/core/pixiv/pixiv_repository.dart
import 'dart:async';
import 'package:dio/dio.dart';

import '../engine/base_image_source.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';
import 'pixiv_client.dart';

// PixivPreferences 类保持不变
class PixivPreferences {
  final String imageQuality;
  final List<String> mutedTags;
  final bool showAi;

  const PixivPreferences({
    this.imageQuality = 'original',
    this.mutedTags = const [],
    this.showAi = true,
  });

  PixivPreferences copyWith({
    String? imageQuality,
    List<String>? mutedTags,
    bool? showAi,
  }) {
    return PixivPreferences(
      imageQuality: imageQuality ?? this.imageQuality,
      mutedTags: mutedTags ?? this.mutedTags,
      showAi: showAi ?? this.showAi,
    );
  }
}

class PixivRepository implements BaseImageSource {
  PixivRepository({
    String? cookie,
    PixivClient? client,
    Dio? dio,
    PrismLogger? logger,
    PixivPagesConfig? pagesConfig,
  })  : _logger = logger,
        _client = client ??
            PixivClient(
              dio: dio,
              cookie: cookie,
              logger: (msg) => logger?.log(msg),
              debugLogger: (msg) => logger?.debug(msg),
            ),
        _pagesConfig = pagesConfig ?? const PixivPagesConfig();

  final PixivClient _client;
  final PrismLogger? _logger;

  PixivPreferences _prefs = const PixivPreferences();
  PixivPagesConfig _pagesConfig;

  PixivPreferences get prefs => _prefs;
  PixivPagesConfig get pagesConfig => _pagesConfig;
  PixivClient get client => _client;
  bool get hasCookie => _client.hasCookie;

  void updatePreferences(PixivPreferences p) => _prefs = p;
  void updatePagesConfig(PixivPagesConfig config) => _pagesConfig = config;

  static const String kRuleId = 'pixiv_search_ajax';
  static const String kUserRuleId = 'pixiv_user';

  // ==================== “阶段 2”缓存（详情补全） ====================

  static const Duration _kDetailCacheTtl = Duration(minutes: 15);
  final Map<String, _DetailCacheEntry> _detailCache = {};

  PixivIllustDetail? _getDetailCache(String id) {
    final e = _detailCache[id];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _kDetailCacheTtl) {
      _detailCache.remove(id);
      return null;
    }
    return e.detail;
  }

  void _setDetailCache(PixivIllustDetail detail) {
    if (detail.id.isEmpty) return;
    _detailCache[detail.id] = _DetailCacheEntry(detail: detail, at: DateTime.now());
  }

  // ==================== 接口实现 ====================

  @override
  bool supports(SourceRule rule) {
    try {
      final id = rule.id;
      if (id == kRuleId) return true;
      if (id == kUserRuleId) return true;
      if (id.startsWith('pixiv')) return true;
    } catch (_) {}
    return false;
  }

  @override
  Future<void> restoreSession({
    required PreferencesStore prefs,
    required SourceRule rule,
  }) async {
    // 1) Cookie
    String? cookieFromPrefs;
    try {
      cookieFromPrefs = await prefs.loadPixivCookie(rule.id);
    } catch (_) {
      cookieFromPrefs = null;
    }

    final h = rule.headers;
    final cookieFromHeaders = ((h?['Cookie'] ?? h?['cookie'])?.toString() ?? '').trim();

    String resolved = (cookieFromPrefs ?? '').trim();
    if (resolved.isEmpty && cookieFromHeaders.isNotEmpty) {
      resolved = cookieFromHeaders;
      try {
        await prefs.savePixivCookie(rule.id, resolved);
      } catch (_) {}
    }

    if (resolved.isNotEmpty) {
      setCookie(resolved);
    }

    // 2) 偏好
    Map<String, dynamic>? raw;
    try {
      raw = await prefs.loadPixivPrefsRaw();
    } catch (_) {
      raw = null;
    }

    if (raw != null) {
      try {
        final mutedRaw = raw['muted_tags'];
        List<String>? muted;
        if (mutedRaw is List) {
          muted = mutedRaw.map((e) => e.toString()).toList();
        } else if (mutedRaw is String && mutedRaw.trim().isNotEmpty) {
          muted = mutedRaw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        }

        updatePreferences(
          _prefs.copyWith(
            imageQuality: raw['quality']?.toString(),
            showAi: raw['show_ai'] == true,
            mutedTags: muted,
          ),
        );
      } catch (_) {}
    }
  }

  @override
  Future<bool> checkLoginStatus(SourceRule rule) async {
    return await _getLoginOkCached();
  }

  @override
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    _syncConfigFromRule(rule);

    // ✅ 空参数兜底
    String finalQuery = (query ?? '').trim();
    if (finalQuery.isEmpty) {
      finalQuery = (rule.defaultKeyword ?? '').trim();
    }
    if (finalQuery.isEmpty) {
      finalQuery = 'ranking_daily';
      _logger?.debug('PixivRepo: fallback to ranking_daily');
    }

    // Filters
    String order = 'date_d';
    String mode = 'all';
    String sMode = 's_tag';
    int minBookmarks = 0;

    final fp = filterParams ?? const <String, dynamic>{};

    String _pickStr(String k, String fallback) {
      final v = fp[k];
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? fallback : s;
    }

    order = _pickStr('order', order);
    mode = _pickStr('mode', mode);
    sMode = _pickStr('s_mode', sMode);

    final mbRaw = fp['min_bookmarks'];
    if (mbRaw != null) {
      minBookmarks = int.tryParse(mbRaw.toString()) ?? 0;
    }

    // 登录态
    final bool loginOk = await _getLoginOkCached();

    bool isRanking = false;
    String rankingMode = '';

    if (mode.startsWith('ranking_')) {
      isRanking = true;
      rankingMode = mode.replaceFirst('ranking_', '');
    } else if (['daily', 'weekly', 'monthly', 'rookie', 'original', 'male', 'female'].contains(mode)) {
      isRanking = true;
      rankingMode = mode;
    }

    if (!loginOk) {
      if (order.toLowerCase().contains('popular')) order = 'date_d';
      if (mode.toLowerCase() == 'r18') mode = 'safe';
    }

    // ✅ user: 通配能力（用户名 / userId 都可）
    // UI 详情页的“查看该作者更多作品”传的是 userName，因此必须在这里解析。
    final bool isUserQuery = finalQuery.toLowerCase().startsWith('user:');
    String userKey = '';
    if (isUserQuery) {
      userKey = finalQuery.substring('user:'.length).trim();
    }

    // 构造查询（非 user:）
    String apiQuery = finalQuery;
    if (!isRanking && !isUserQuery && finalQuery.isNotEmpty && minBookmarks > 0) {
      apiQuery = '$finalQuery ${minBookmarks}users入り';
    }

    _logger?.log(
      'REQ pixiv q="$finalQuery"(api="$apiQuery") page=$page order=$order mode=$mode(rank=$isRanking) login=${loginOk ? 1 : 0}',
    );

    final ruleId = rule.id;
    List<PixivIllustBrief> briefs = [];

    try {
      if (isRanking) {
        briefs = await _client.getRanking(mode: rankingMode, page: page);
      } else if (ruleId == kUserRuleId || isUserQuery) {
        // ✅ user: 分支
        final resolvedUserId = await _resolveUserId(userKey.isNotEmpty ? userKey : apiQuery);
        if (resolvedUserId.isEmpty) return const [];
        briefs = await _client.getUserArtworks(userId: resolvedUserId, page: page);
      } else {
        if (apiQuery.isEmpty) return const [];
        briefs = await _client.searchArtworks(
          word: apiQuery,
          page: page,
          order: order,
          mode: mode,
          sMode: sMode,
        );
      }
    } catch (e) {
      _logger?.log('ERR pixiv fetch: $e');
      rethrow;
    }

    // 过滤（AI & muted tags）
    briefs = briefs.where((b) {
      if (!_prefs.showAi && b.isAi) return false;
      if (_prefs.mutedTags.isNotEmpty) {
        for (final t in b.tags) {
          if (_prefs.mutedTags.contains(t)) return false;
        }
      }
      return true;
    }).toList();

    _logger?.log('RESP pixiv count=${briefs.length}');
    if (briefs.isEmpty) return const [];

    // ✅ “两阶段优化”：
    // 阶段 1：brief 已经有 tags/userName 的先用
    // 阶段 2：并发补全 pages + detail（上传者/真实 tags/浏览收藏/创建时间）
    final enriched = await _enrichWithPagesAndDetail(
      briefs,
      concurrency: _pagesConfig.concurrency,
      timeoutPerItem: _pagesConfig.timeoutPerItem,
    );

    final out = <UniWallpaper>[];
    for (final e in enriched) {
      if (e.id.isEmpty) continue;

      // 图片质量选择
      String bestUrl = e.thumbUrl;
      switch (_prefs.imageQuality) {
        case 'original':
          bestUrl = e.originalUrl.isNotEmpty ? e.originalUrl : (e.regularUrl.isNotEmpty ? e.regularUrl : e.thumbUrl);
          break;
        case 'small':
          bestUrl = e.thumbUrl;
          break;
        case 'regular':
        default:
          bestUrl = e.regularUrl.isNotEmpty ? e.regularUrl : (e.originalUrl.isNotEmpty ? e.originalUrl : e.thumbUrl);
          break;
      }

      // mimeType：尽量从 bestUrl 推断
      final mimeType = _guessMimeType(bestUrl);

      // createdAt：尽量只取日期部分（UI 当前按字符串展示）
      final createdAt = _formatDateOnly(e.createDate);

      out.add(
        UniWallpaper(
          id: e.id,
          sourceId: 'pixiv',
          thumbUrl: e.thumbUrl,
          fullUrl: bestUrl,
          width: (e.width > 0 ? e.width : e.detailWidth).toDouble(),
          height: (e.height > 0 ? e.height : e.detailHeight).toDouble(),
          grade: e.grade,
          isUgoira: e.isUgoira,
          isAi: e.isAi,
          tags: e.tags,

          // ✅ 详情页关键字段：修复“识别不准”
          uploader: e.uploader.isNotEmpty ? e.uploader : 'Unknown User',
          views: e.viewCount > 0 ? e.viewCount.toString() : '',
          favorites: e.bookmarkCount > 0 ? e.bookmarkCount.toString() : '',
          createdAt: createdAt,
          mimeType: mimeType,
          // fileSize pixiv ajax 不稳定/不可用：暂留空
          fileSize: '',
        ),
      );
    }

    return out;
  }

  // ==================== 辅助与并发控制 ====================

  void setCookie(String? cookie) {
    _client.setCookie(cookie);
    _invalidateLoginCache();
    final len = (cookie ?? '').trim().length;
    if (len > 0) {
      _logger?.log('PixivRepo: setCookie updated (len=$len)');
    } else {
      _logger?.log('PixivRepo: setCookie cleared');
    }
    _logger?.debug('PixivRepo: client.hasCookie=${_client.hasCookie}');
  }

  Map<String, String> buildImageHeaders() => _client.buildImageHeaders();

  static const Duration _kLoginCacheTtl = Duration(minutes: 5);
  bool? _cachedLoginOk;
  DateTime? _cachedLoginAt;

  // ✅ 并发锁
  Future<bool>? _checkingLoginFuture;

  bool? get cachedLoginOk => _cachedLoginOk;

  void _invalidateLoginCache() {
    _cachedLoginOk = null;
    _cachedLoginAt = null;
  }

  Future<bool> _getLoginOkCached() async {
    if (!hasCookie) {
      _cachedLoginOk = false;
      _cachedLoginAt = DateTime.now();
      return false;
    }

    final now = DateTime.now();
    final lastAt = _cachedLoginAt;
    final lastOk = _cachedLoginOk;

    if (lastAt != null && lastOk != null) {
      final age = now.difference(lastAt);
      if (age <= _kLoginCacheTtl) {
        return lastOk;
      }
    }

    final existingFuture = _checkingLoginFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final completer = Completer<bool>();
    _checkingLoginFuture = completer.future;

    (() async {
      try {
        final ok = await _client.checkLogin();
        _cachedLoginOk = ok;
        _cachedLoginAt = DateTime.now();
        if (!completer.isCompleted) completer.complete(ok);
      } catch (_) {
        _cachedLoginOk = false;
        _cachedLoginAt = DateTime.now();
        if (!completer.isCompleted) completer.complete(false);
      } finally {
        if (_checkingLoginFuture == completer.future) {
          _checkingLoginFuture = null;
        }
      }
    })();

    return completer.future;
  }

  Future<bool> getLoginOk(dynamic rule) async {
    _syncConfigFromRule(rule);
    return _getLoginOkCached();
  }

  void _syncConfigFromRule(dynamic rule) {
    try {
      final dynamic headers = (rule as dynamic).headers;
      if (headers == null || headers is! Map) return;

      final dynamic c1 = headers['Cookie'];
      final dynamic c2 = headers['cookie'];
      final cookie = (c1 ?? c2)?.toString().trim();

      final dynamic ua1 = headers['User-Agent'];
      final dynamic ua2 = headers['user-agent'];
      final ua = (ua1 ?? ua2)?.toString().trim();

      if ((cookie != null && cookie.isNotEmpty) || (ua != null && ua.isNotEmpty)) {
        if (cookie != null && cookie.isNotEmpty && cookie != _client.buildImageHeaders()['Cookie']) {
          _client.updateConfig(cookie: cookie, userAgent: ua);
          _invalidateLoginCache();
        } else if (ua != null && ua.isNotEmpty) {
          _client.updateConfig(userAgent: ua);
        }
      }
    } catch (e) {
      _logger?.log('PixivRepo: config sync failed: $e');
    }
  }

  Future<String> _resolveUserId(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return '';

    // 数字：直接当 userId
    if (_isNumeric(q)) return q;

    // 非数字：用 users 搜索解析
    final resolved = await _client.resolveUserIdByName(q);
    return (resolved ?? '').trim();
  }

  bool _isNumeric(String s) {
    if (s.isEmpty) return false;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
    }
    return true;
  }

  Future<List<_PixivEnriched>> _enrichWithPagesAndDetail(
    List<PixivIllustBrief> briefs, {
    int concurrency = 4,
    Duration timeoutPerItem = const Duration(seconds: 8),
  }) async {
    if (briefs.isEmpty) return const [];

    final List<_PixivEnriched?> results = List<_PixivEnriched?>.filled(briefs.length, null, growable: false);
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

        // 基础信息（阶段 1）
        String regular = '';
        String original = _deriveOriginalFromThumb(b.thumbUrl) ?? '';
        final grade = _gradeFromRestrict(b.xRestrict);

        final bool needPagesFetch = (_prefs.imageQuality != 'small') && original.isEmpty;

        // pages 补全（原图/常规图）
        if (needPagesFetch) {
          try {
            final pages = await _client.getIllustPages(b.id).timeout(timeoutPerItem);
            if (pages.isNotEmpty) {
              final p0 = pages.first;
              if (p0.regular.isNotEmpty) regular = p0.regular;
              if (p0.original.isNotEmpty) original = p0.original;
            }
          } catch (_) {}
        } else {
          if (regular.isEmpty) regular = original;
        }

        // detail 补全（阶段 2）
        PixivIllustDetail? detail = _getDetailCache(b.id);
        if (detail == null) {
          try {
            detail = await _client.getIllustDetail(b.id).timeout(timeoutPerItem);
            if (detail != null) {
              _setDetailCache(detail);
            }
          } catch (_) {
            detail = null;
          }
        }

        final uploader = (b.userName.trim().isNotEmpty)
            ? b.userName.trim()
            : (detail?.userName.trim().isNotEmpty ?? false)
                ? detail!.userName.trim()
                : '';

        final tags = _mergeTags(primary: detail?.tags ?? const [], secondary: b.tags);

        final viewCount = (b.viewCount > 0) ? b.viewCount : (detail?.viewCount ?? 0);
        final bookmarkCount = (b.bookmarkCount > 0) ? b.bookmarkCount : (detail?.bookmarkCount ?? 0);

        final createDate = (b.createDate.trim().isNotEmpty) ? b.createDate.trim() : (detail?.createDate ?? '');

        results[idx] = _PixivEnriched(
          id: b.id,
          thumbUrl: b.thumbUrl,
          regularUrl: regular,
          originalUrl: original,
          width: b.width,
          height: b.height,
          detailWidth: detail?.width ?? 0,
          detailHeight: detail?.height ?? 0,
          grade: grade,
          isUgoira: b.isUgoira || (detail?.isUgoira ?? false),
          isAi: b.isAi || (detail?.isAi ?? false),
          uploader: uploader,
          tags: tags,
          viewCount: viewCount,
          bookmarkCount: bookmarkCount,
          createDate: createDate,
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

  List<String> _mergeTags({required List<String> primary, required List<String> secondary}) {
    final set = <String>{};
    for (final t in primary) {
      final s = t.trim();
      if (s.isNotEmpty) set.add(s);
    }
    for (final t in secondary) {
      final s = t.trim();
      if (s.isNotEmpty) set.add(s);
    }
    return set.toList(growable: false);
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
      newPath = newPath.replaceAll('_square1200', '').replaceAll('_master1200', '').replaceAll('_custom1200', '');
      return u.replace(path: newPath, query: '').toString();
    } catch (_) {
      return null;
    }
  }

  String _guessMimeType(String url) {
    final u = url.toLowerCase();
    if (u.contains('.png')) return 'image/png';
    if (u.contains('.webp')) return 'image/webp';
    if (u.contains('.gif')) return 'image/gif';
    if (u.contains('.jpeg') || u.contains('.jpg')) return 'image/jpeg';
    // pixiv 原图有时无后缀，保守返回 jpeg
    return 'image/jpeg';
  }

  String _formatDateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    // 常见：2024-01-02T12:34:56+09:00
    final t = s.indexOf('T');
    if (t > 0) return s.substring(0, t);
    // 或已经是 YYYY-MM-DD
    if (s.length >= 10) return s.substring(0, 10);
    return s;
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
}

class _PixivEnriched {
  final String id;
  final String thumbUrl;
  final String regularUrl;
  final String originalUrl;

  final int width;
  final int height;

  // detail fallback
  final int detailWidth;
  final int detailHeight;

  final String? grade;
  final bool isUgoira;
  final bool isAi;

  // ✅ 详情页关键字段
  final String uploader;
  final List<String> tags;
  final int viewCount;
  final int bookmarkCount;
  final String createDate;

  const _PixivEnriched({
    required this.id,
    required this.thumbUrl,
    required this.regularUrl,
    required this.originalUrl,
    required this.width,
    required this.height,
    required this.detailWidth,
    required this.detailHeight,
    required this.grade,
    required this.isUgoira,
    required this.isAi,
    required this.uploader,
    required this.tags,
    required this.viewCount,
    required this.bookmarkCount,
    required this.createDate,
  });
}

class _DetailCacheEntry {
  final PixivIllustDetail detail;
  final DateTime at;
  const _DetailCacheEntry({required this.detail, required this.at});
}