// lib/core/pixiv/pixiv_repository.dart
import 'dart:async';
import 'package:dio/dio.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../storage/preferences_store.dart'; // ✅
import '../utils/prism_logger.dart';
import '../engine/base_image_source.dart'; // ✅
import 'pixiv_client.dart';

// PixivPreferences 类保持不变
class PixivPreferences {
  final String imageQuality;
  final List<String> mutedTags;
  final bool showAi;
  const PixivPreferences({this.imageQuality = 'original', this.mutedTags = const [], this.showAi = true});
  PixivPreferences copyWith({String? imageQuality, List<String>? mutedTags, bool? showAi}) {
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
    // 1. 恢复 Cookie
    String? cookieFromPrefs;
    try {
      cookieFromPrefs = await prefs.loadPixivCookie(rule.id);
    } catch (e) {
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

    // 2. 恢复偏好
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
    // 同步配置
    _syncConfigFromRule(rule);

    // ✅ 空参数兜底逻辑 (下沉到这里)
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

    // 构造查询
    String apiQuery = finalQuery;
    if (!isRanking && finalQuery.isNotEmpty && minBookmarks > 0) {
      apiQuery = '$finalQuery ${minBookmarks}users入り';
    }

    _logger?.log(
      'REQ pixiv q="$apiQuery" page=$page order=$order mode=$mode(rank=$isRanking) login=${loginOk ? 1 : 0}',
    );

    final ruleId = rule.id;
    List<PixivIllustBrief> briefs = [];

    try {
      if (isRanking) {
        briefs = await _client.getRanking(mode: rankingMode, page: page);
      } else if (ruleId == kUserRuleId) {
        briefs = await _client.getUserArtworks(userId: apiQuery, page: page);
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

    // 过滤
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

    // 并发补全
    final enriched = await _enrichWithPages(
      briefs,
      concurrency: _pagesConfig.concurrency,
      timeoutPerItem: _pagesConfig.timeoutPerItem,
    );

    final out = <UniWallpaper>[];
    for (final e in enriched) {
      if (e.id.isEmpty) continue;

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

      out.add(
        UniWallpaper(
          id: e.id,
          sourceId: 'pixiv',
          thumbUrl: e.thumbUrl,
          fullUrl: bestUrl,
          width: e.width.toDouble(),
          height: e.height.toDouble(),
          grade: e.grade,
          isUgoira: e.isUgoira,
          isAi: e.isAi,
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
  
  // ✅ Completer 并发锁
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
    // ✅ 局部捕获，防止 Race Condition
    final lastAt = _cachedLoginAt;
    final lastOk = _cachedLoginOk;

    if (lastAt != null && lastOk != null) {
      final age = now.difference(lastAt);
      if (age <= _kLoginCacheTtl) {
        return lastOk;
      }
    }

    // ✅ Completer 逻辑
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
      } catch (e) {
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

  Future<List<_PixivEnriched>> _enrichWithPages(
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
        String regular = '';
        String original = _deriveOriginalFromThumb(b.thumbUrl) ?? '';
        final grade = _gradeFromRestrict(b.xRestrict);
        final bool needFetch = (_prefs.imageQuality != 'small') && original.isEmpty;

        if (needFetch) {
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

        results[idx] = _PixivEnriched(
          id: b.id,
          thumbUrl: b.thumbUrl,
          regularUrl: regular,
          originalUrl: original,
          width: b.width,
          height: b.height,
          grade: grade,
          isUgoira: b.isUgoira,
          isAi: b.isAi,
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
      newPath = newPath.replaceAll('_square1200', '').replaceAll('_master1200', '').replaceAll('_custom1200', '');
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
}

class _PixivEnriched {
  final String id;
  final String thumbUrl;
  final String regularUrl;
  final String originalUrl;
  final int width;
  final int height;
  final String? grade;
  final bool isUgoira;
  final bool isAi;

  const _PixivEnriched({
    required this.id,
    required this.thumbUrl,
    required this.regularUrl,
    required this.originalUrl,
    required this.width,
    required this.height,
    required this.grade,
    required this.isUgoira,
    required this.isAi,
  });
}
