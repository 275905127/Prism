// lib/core/pixiv/pixiv_client.dart
import 'package:dio/dio.dart';

class PixivClient {
  final Dio _dio;
  String? _cookie;

  /// 全局统一的 Mobile UA (Android Chrome)
  static const String kMobileUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  String _userAgent = kMobileUserAgent;

  /// 普通日志（关键业务 / 结论 / 错误）
  final void Function(String msg)? _log;

  /// Debug 日志（高频 / 打点）
  final void Function(String msg)? _debug;

  // 只注入一次，避免重复 add 导致刷屏/臃肿
  late final Interceptor _debugInterceptor;

  PixivClient({
    Dio? dio,
    String? cookie,
    void Function(String msg)? logger,
    void Function(String msg)? debugLogger,
  })  : _dio = dio ?? Dio(),
        _cookie = (cookie ?? '').trim().isEmpty ? null : cookie!.trim(),
        _log = logger,
        _debug = debugLogger {
    _dio.options = _dio.options.copyWith(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    );

    _debugInterceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        // 高频：只走 debug
        final hasC = (options.headers['Cookie']?.toString().trim().isNotEmpty ?? false);
        _debug?.call(
          'PixivClient REQ ${options.method} ${options.baseUrl}${options.path} hasCookie=${hasC ? 1 : 0}',
        );
        handler.next(options);
      },
      onResponse: (resp, handler) {
        // 高频：只走 debug
        _debug?.call('PixivClient RESP ${resp.statusCode} ${resp.requestOptions.path}');
        handler.next(resp);
      },
      onError: (e, handler) {
        // 关键：错误必须保留在普通日志
        final sc = e.response?.statusCode;
        _log?.call('PixivClient ERR ${e.type} ${e.requestOptions.path} status=${sc ?? 'N/A'} $e');
        handler.next(e);
      },
    );

    _installDebugInterceptors();
    _refreshHeaders(forceLog: true);
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  /// 仅当 cookie/ua 实际变化时才刷新 headers，减少“点位日志”频率
  void updateConfig({String? cookie, String? userAgent}) {
    bool changed = false;

    if (cookie != null) {
      final c = cookie.trim();
      final next = c.isEmpty ? null : c;
      if (next != _cookie) {
        _cookie = next;
        changed = true;
      }
    }

    if (userAgent != null) {
      final ua = userAgent.trim();
      if (ua.isNotEmpty && ua != _userAgent) {
        _userAgent = ua;
        changed = true;
      }
    }

    if (!changed) return;

    _refreshHeaders(forceLog: false);

    // 这里不再输出“每次变更详情”，避免臃肿
    // 需要定位时再开 debug 即可
    _debug?.call(
      'PixivClient.updateConfig applied hasCookie=${hasCookie ? 1 : 0} cookieLen=${(_cookie ?? '').length} uaLen=${_userAgent.length}',
    );
  }

  void setCookie(String? cookie) {
    updateConfig(cookie: cookie ?? '');
  }

  void _refreshHeaders({required bool forceLog}) {
    final headers = <String, dynamic>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    if (hasCookie) headers['Cookie'] = _cookie!;
    _dio.options.headers = headers;

    // 初始化时打一条，之后只走 debug（避免刷屏）
    if (forceLog) {
      _log?.call(
        'PixivClient headers ready hasCookie=${hasCookie ? 1 : 0} uaLen=${_userAgent.length}',
      );
    } else {
      _debug?.call(
        'PixivClient.refreshHeaders hasCookie=${hasCookie ? 1 : 0} keys=${headers.keys.toList()}',
      );
    }
  }

  Map<String, String> buildImageHeaders() {
    final out = <String, String>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
    };
    if (hasCookie) out['Cookie'] = _cookie!;
    return out;
  }

  void _installDebugInterceptors() {
    // 不要 removeWhere(InterceptorsWrapper)，会误伤其他模块的拦截器
    // 只保证“本拦截器”只注入一次
    final exists = _dio.interceptors.any((i) => identical(i, _debugInterceptor));
    if (!exists) {
      _dio.interceptors.add(_debugInterceptor);
    }
  }

  // =========================================================
  // API 方法
  // =========================================================

  Future<bool> checkLogin() async {
    // 没 cookie 属于常态，不打普通日志；需要定位再开 debug
    if (!hasCookie) {
      _debug?.call('PixivClient.checkLogin skip (no cookie)');
      return false;
    }

    try {
      final resp = await _dio.get('/ajax/user/self');
      final sc = resp.statusCode ?? 0;

      if (sc >= 400) {
        // 可能是过期/无权限：不算“错误”，只记 debug
        _debug?.call('PixivClient.checkLogin status=$sc -> false');
        return false;
      }

      final data = resp.data;
      if (data is! Map) {
        _debug?.call('PixivClient.checkLogin invalid data type=${data.runtimeType}');
        return false;
      }

      if (data['body'] is Map) {
        final uid = (data['body']['userId']?.toString() ?? '').trim();
        if (uid.isNotEmpty) {
          _debug?.call('PixivClient.checkLogin ok userId=$uid');
          return true;
        }
      }

      if (data['userData'] is Map) {
        final uid = (data['userData']['id']?.toString() ?? '').trim();
        if (uid.isNotEmpty) {
          _debug?.call('PixivClient.checkLogin ok userId=$uid');
          return true;
        }
      }

      _debug?.call('PixivClient.checkLogin userId not found');
      return false;
    } catch (e) {
      // 真异常：必须进普通日志
      _log?.call('PixivClient.checkLogin exception: $e');
      return false;
    }
  }

  Future<List<PixivIllustBrief>> searchArtworks({
    required String word,
    int page = 1,
    String order = 'date_d',
    String mode = 'all',
    String sMode = 's_tag',
  }) async {
    if (word.trim().isEmpty) return [];

    try {
      final resp = await _dio.get(
        '/ajax/search/artworks/${Uri.encodeComponent(word)}',
        queryParameters: {
          'word': word,
          'order': order,
          'mode': mode,
          's_mode': sMode,
          'p': page,
          'type': 'illust_and_ugoira',
        },
      );

      if ((resp.statusCode ?? 0) >= 400) return [];

      final data = resp.data;
      if (data is! Map) return [];

      final body = data['body'];
      if (body is! Map) return [];

      final container = body['illustManga'] ?? body['illust'];
      if (container is! Map) return [];

      final list = container['data'];
      if (list is! List) return [];

      return list
          .map((e) => PixivIllustBrief.fromJson(e))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (e) {
      // 这里不刷屏：保留异常到普通日志（便于定位网络/解析问题）
      _log?.call('PixivClient.searchArtworks exception: $e');
      return [];
    }
  }

  Future<List<PixivIllustBrief>> getRanking({
    required String mode,
    int page = 1,
  }) async {
    try {
      final resp = await _dio.get(
        '/touch/ajax/ranking',
        queryParameters: {
          'mode': mode,
          'type': 'all',
          'p': page,
          'format': 'json',
        },
      );

      if ((resp.statusCode ?? 0) >= 400) return [];

      final body = resp.data;
      if (body is! Map) return [];

      final rankings = body['ranking'] ?? (body['body']?['ranking']);
      if (rankings is! List) return [];

      return rankings.map((e) => PixivIllustBrief.fromMap(e)).toList();
    } catch (e) {
      _log?.call('PixivClient.getRanking exception: $e');
      return [];
    }
  }

  Future<List<PixivPageUrls>> getIllustPages(String illustId) async {
    if (illustId.isEmpty) return [];
    try {
      final resp = await _dio.get('/ajax/illust/$illustId/pages');
      if ((resp.statusCode ?? 0) >= 400) return [];

      final data = resp.data;
      if (data is! Map) return [];

      final body = data['body'];
      if (body is! List) return [];

      return body.map((e) => PixivPageUrls.fromJson(e)).toList();
    } catch (e) {
      _log?.call('PixivClient.getIllustPages exception: $e');
      return [];
    }
  }

  Future<List<PixivIllustBrief>> getUserArtworks({
    required String userId,
    int page = 1,
  }) async {
    if (userId.isEmpty) return [];
    try {
      final resp = await _dio.get(
        '/touch/ajax/user/illusts',
        queryParameters: {'user_id': userId, 'p': page},
      );

      final data = resp.data;
      if (data is! Map) return [];
      final body = data['body'];
      if (body is! Map) return [];
      final list = body['illusts'];
      if (list is! List) return [];

      return list.map((e) => PixivIllustBrief.fromMap(e)).toList();
    } catch (e) {
      _log?.call('PixivClient.getUserArtworks exception: $e');
      return [];
    }
  }
}