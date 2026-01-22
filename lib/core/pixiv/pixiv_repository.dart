// lib/core/pixiv/pixiv_repository.dart
import 'dart:async';
import 'package:dio/dio.dart';
import '../models/uni_wallpaper.dart';
import '../utils/prism_logger.dart';
import 'pixiv_client.dart';

// Pixiv 偏好设置类
class PixivPreferences {
  final String imageQuality; // 'original', 'regular', 'small'
  final List<String> mutedTags; // 屏蔽标签列表
  final bool showAi; // 是否显示 AI 作品 (false = 屏蔽 aiType==2)

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

class PixivRepository {
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
              // 关键日志走 log，高频走 debug
              logger: (msg) => logger?.log(msg),
              debugLogger: (msg) => logger?.debug(msg),
            ),
        _pagesConfig = pagesConfig ?? const PixivPagesConfig();

  final PixivClient _client;
  final PrismLogger? _logger;

  PixivPreferences _prefs = const PixivPreferences();
  PixivPreferences get prefs => _prefs;
  void updatePreferences(PixivPreferences p) => _prefs = p;

  static const String kRuleId = 'pixiv_search_ajax';
  static const String kUserRuleId = 'pixiv_user';

  PixivClient get client => _client;

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

  PixivPagesConfig _pagesConfig;
  PixivPagesConfig get pagesConfig => _pagesConfig;

  void updatePagesConfig(PixivPagesConfig config) {
    _pagesConfig = config;
  }

  // ---------- Login check cache ----------
  static const Duration _kLoginCacheTtl = Duration(minutes: 5);
  bool? _cachedLoginOk;
  DateTime? _cachedLoginAt;
  
  // 使用 Future 变量配合 Completer 消除 Race Condition
  Future<bool>? _checkingLoginFuture;

  bool? get cachedLoginOk => _cachedLoginOk;

  void _invalidateLoginCache() {
    _cachedLoginOk = null;
    _cachedLoginAt = null;
    // 不置空 _checkingLoginFuture，让其自然结束
  }

  Future<bool> _getLoginOkCached() async {
    if (!hasCookie) {
      _cachedLoginOk = false;
      _cachedLoginAt = DateTime.now();
      _logger?.debug('PixivRepo: login=false (no cookie)');
      return false;
    }

    final now = DateTime.now();
    // ✅ 修复：局部变量捕获，绝对不使用 ! 操作符
    final lastAt = _cachedLoginAt;
    final lastOk = _cachedLoginOk;

    if (lastAt != null && lastOk != null) {
      final age = now.difference(lastAt);
      if (age <= _kLoginCacheTtl) {
        _logger?.debug('PixivRepo: login cache hit -> $lastOk age=${age.inSeconds}s');
        return lastOk;
      }
    }

    // ✅ 修复：局部变量捕获 Future，防止成员变量在判断后被置空
    final existingFuture = _checkingLoginFuture;
    if (existingFuture != null) {
      _logger?.debug('PixivRepo: login check already running -> await');
      return existingFuture;
    }

    final completer = Completer<bool>();
    _checkingLoginFuture = completer.future;

    // 启动异步任务
    (() async {
      try {
        _logger?.log('PixivRepo: login check start');
        final ok = await _client.checkLogin();
        _cachedLoginOk = ok;
        _cachedLoginAt = DateTime.now();
        _logger?.log('PixivRepo: login check done -> $ok');
        if (!completer.isCompleted) completer.complete(ok);
      } catch (e) {
        _cachedLoginOk = false;
        _cachedLoginAt = DateTime.now();
        _logger?.log('PixivRepo: login check exception -> false error=$e');
        if (!completer.isCompleted) completer.complete(false);
      } finally {
        // 只有当当前的 future 就是我们创建的这个时，才清除（防止清除掉别人新创建的）
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

  // ---------- Config sync ----------
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

  /// Fetch 入口
  Future<List<UniWallpaper>> fetch(
    dynamic rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final String baseQuery = (query ?? '').trim();
    _syncConfigFromRule(rule);

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

    // 登录态判断 (使用安全版本)
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

    String finalQuery = baseQuery;
    if (!isRanking && baseQuery.isNotEmpty && minBookmarks > 0) {
      finalQuery = '$baseQuery ${minBookmarks}users入り';
    }

    _logger?.log(
      'REQ pixiv q="$finalQuery" page=$page order=$order mode=$mode(rank=$isRanking) login=${loginOk ? 1 : 0}',
    );

    final ruleId = (rule as dynamic).id?.toString() ?? '';
    List<PixivIllustBrief> briefs = [];

    try {
      if (isRanking) {
        briefs = await _client.getRanking(mode: rankingMode, page: page);
      } else if (ruleId == kUserRuleId) {
        briefs = await _client.getUserArtworks(userId: finalQuery, page: page);
      } else {
        if (finalQuery.isEmpty) return const [];
        briefs = await _client.searchArtworks(
          word: finalQuery,
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

    // 客户端过滤
    final int beforeCount = briefs.length;
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
          } catch (_) {
            // ignore
          }
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
