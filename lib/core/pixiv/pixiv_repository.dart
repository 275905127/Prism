// lib/core/pixiv/pixiv_repository.dart
import 'dart:async'; // ✅ 新增引用
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

  // 偏好设置状态
  PixivPreferences _prefs = const PixivPreferences();
  PixivPreferences get prefs => _prefs;
  void updatePreferences(PixivPreferences p) => _prefs = p;

  static const String kRuleId = 'pixiv_search_ajax';
  static const String kUserRuleId = 'pixiv_user';

  // 暴露 Client 给 Service 使用
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

  // Cookie 设置逻辑（关键点保留，高频点 debug）
  void setCookie(String? cookie) {
    _client.setCookie(cookie);
    _invalidateLoginCache();

    final len = (cookie ?? '').trim().length;
    if (len > 0) {
      _logger?.log('PixivRepo: setCookie updated (len=$len)');
    } else {
      _logger?.log('PixivRepo: setCookie cleared');
    }

    // 高频状态点：默认不刷屏
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
  
  // ✅ 修复：使用 Future 变量配合 Completer 消除 Race Condition
  Future<bool>? _checkingLoginFuture;

  bool? get cachedLoginOk => _cachedLoginOk;

  void _invalidateLoginCache() {
    _cachedLoginOk = null;
    _cachedLoginAt = null;
    // 注意：这里不要暴力置空 _checkingLoginFuture，让正在进行的检查自然完成
  }

  Future<bool> _getLoginOkCached() async {
    if (!hasCookie) {
      _cachedLoginOk = false;
      _cachedLoginAt = DateTime.now();
      // 低频但有解释性：保留
      _logger?.log('PixivRepo: login=false (no cookie)');
      return false;
    }

    final now = DateTime.now();
    final lastAt = _cachedLoginAt;
    if (lastAt != null && _cachedLoginOk != null) {
      final age = now.difference(lastAt);
      if (age <= _kLoginCacheTtl) {
        // cache 命中属于高频：debug
        _logger?.debug('PixivRepo: login cache hit -> ${_cachedLoginOk!} age=${age.inSeconds}s');
        return _cachedLoginOk!;
      }
    }

    // ✅ 修复核心：如果正在检查，直接返回同一个 Future，防止 null check 错误
    if (_checkingLoginFuture != null) {
      _logger?.debug('PixivRepo: login check already running -> await');
      return _checkingLoginFuture!;
    }

    // 创建 Completer 来控制流程
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
        completer.complete(ok);
      } catch (e) {
        _cachedLoginOk = false;
        _cachedLoginAt = DateTime.now();
        _logger?.log('PixivRepo: login check exception -> false error=$e');
        completer.complete(false);
      } finally {
        // 只有在任务完全结束后才清除 Future 引用
        _checkingLoginFuture = null;
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

      // 只有当规则里真的有 cookie/ua 时才覆盖，否则保持当前态
      if ((cookie != null && cookie.isNotEmpty) || (ua != null && ua.isNotEmpty)) {
        // 简单的去重检查：如果和现有的一样就不触发 setCookie
        if (cookie != null && cookie.isNotEmpty && cookie != _client.buildImageHeaders()['Cookie']) {
           _client.updateConfig(cookie: cookie, userAgent: ua);
           _invalidateLoginCache();
           _logger?.debug('PixivRepo: config synced: Cookie injected (len=${cookie.length})');
        } else if (ua != null && ua.isNotEmpty) {
           _client.updateConfig(userAgent: ua);
           _logger?.debug('PixivRepo: config synced: UA updated');
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

    // 1. 同步配置
    _syncConfigFromRule(rule);

    // 2. 读取 filters
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

    // 3. 登录态判断
    final bool loginOk = await _getLoginOkCached();

    // 4. 降级与权限
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
      if (order.toLowerCase().contains('popular')) {
        _logger?.log('PixivRepo: blocked: order=$order -> date_d');
        order = 'date_d';
      }
      if (mode.toLowerCase() == 'r18') {
        _logger?.log('PixivRepo: blocked: mode=r18 -> safe');
        mode = 'safe';
      }
    }

    // 5. 构造最终 Query
    String finalQuery = baseQuery;
    if (!isRanking && baseQuery.isNotEmpty && minBookmarks > 0) {
      finalQuery = '$baseQuery ${minBookmarks}users入り';
    }

    // 核心请求日志：保留一行即可
    _logger?.log(
      'REQ pixiv q="$finalQuery" page=$page order=$order mode=$mode(rank=$isRanking) login=${loginOk ? 1 : 0}',
    );

    // cookie 是否存在属于高频细节：debug
    _logger?.debug('PixivRepo: cookie=${hasCookie ? 1 : 0}');

    // 6. 执行 API
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

    // 7. 客户端过滤
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

    if (briefs.length != beforeCount) {
      _logger?.debug('PixivRepo: muted filtered: ${beforeCount - briefs.length} removed');
    }

    _logger?.log('RESP pixiv count=${briefs.length}');
    if (briefs.isEmpty) return const [];

    // 8. 并发补全
    final enriched = await _enrichWithPages(
      briefs,
      concurrency: _pagesConfig.concurrency,
      timeoutPerItem: _pagesConfig.timeoutPerItem,
      retryCount: _pagesConfig.retryCount,
      retryDelay: _pagesConfig.retryDelay,
    );

    // 9. 转换结果
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
    int retryCount = 1,
    Duration retryDelay = const Duration(milliseconds: 280),
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
          // pages 并发请求非常高频：完全静默（失败也不刷屏）
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
