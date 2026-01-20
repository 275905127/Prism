// lib/core/pixiv/pixiv_client.dart
import 'package:dio/dio.dart';

class PixivClient {
  final Dio _dio;
  String? _cookie;

  // 🔥 全局统一的 Mobile UA (Android Chrome)
  static const String kMobileUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  String _userAgent = kMobileUserAgent;

  final void Function(String msg)? _log;

  PixivClient({
    Dio? dio,
    String? cookie,
    void Function(String msg)? logger,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie,
        _log = logger {
    _dio.options = _dio.options.copyWith(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500,
    );

    _installDebugInterceptors();
    _refreshHeaders();
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  void updateConfig({String? cookie, String? userAgent}) {
    bool changed = false;

    // cookie 允许传 null（表示清空），但空字符串也当作清空
    if (cookie != null) {
      final c = cookie.trim();
      _cookie = c.isEmpty ? null : c;
      changed = true;
    }

    if (userAgent != null && userAgent.trim().isNotEmpty) {
      _userAgent = userAgent.trim();
      changed = true;
    }

    if (changed) {
      _refreshHeaders();
      _log?.call(
        'PixivClient.updateConfig changed: hasCookie=$hasCookie cookieLen=${(_cookie ?? '').length} uaLen=${_userAgent.length}',
      );
    }
  }

  void setCookie(String? cookie) {
    updateConfig(cookie: cookie ?? '');
  }

  void _refreshHeaders() {
    final headers = <String, dynamic>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    if (hasCookie) headers['Cookie'] = _cookie!;
    _dio.options.headers = headers;

    _log?.call(
      'PixivClient._refreshHeaders: hasCookie=$hasCookie cookieLen=${(_cookie ?? '').length} headersKeys=${headers.keys.toList()}',
    );
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
    _dio.interceptors.removeWhere((i) => i is InterceptorsWrapper);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final hasC = (options.headers['Cookie']?.toString().trim().isNotEmpty ?? false);
          final cLen = options.headers['Cookie']?.toString().length ?? 0;
          final uaLen = options.headers['User-Agent']?.toString().length ?? 0;
          _log?.call(
            'PixivClient REQ ${options.method} ${options.baseUrl}${options.path} '
            'hasCookie=$hasC cookieLen=$cLen uaLen=$uaLen',
          );
          handler.next(options);
        },
        onResponse: (resp, handler) {
          _log?.call(
            'PixivClient RESP ${resp.statusCode} ${resp.requestOptions.path} '
            'type=${resp.data.runtimeType}',
          );
          handler.next(resp);
        },
        onError: (e, handler) {
          _log?.call('PixivClient ERR ${e.type} ${e.requestOptions.path} $e');
          handler.next(e);
        },
      ),
    );
  }

  // =========================================================
  // API 方法
  // =========================================================

  Future<bool> checkLogin() async {
    if (!hasCookie) {
      _log?.call('PixivClient.checkLogin: no cookie -> false');
      return false;
    }

    try {
      final resp = await _dio.get('/ajax/user/self');
      final sc = resp.statusCode ?? 0;

      if (sc >= 400) {
        _log?.call('PixivClient.checkLogin: status=$sc -> false');
        return false;
      }

      final data = resp.data;
      if (data is! Map) {
        _log?.call('PixivClient.checkLogin: data not Map (${data.runtimeType}) -> false');
        return false;
      }

      final keys = data.keys.map((e) => e.toString()).toList()..sort();
      _log?.call('PixivClient.checkLogin: bodyKeys=$keys');

      if (data['body'] is Map) {
        final uid = (data['body']['userId']?.toString() ?? '').trim();
        if (uid.isNotEmpty) {
          _log?.call('PixivClient.checkLogin: ok userId=$uid');
          return true;
        }
      }
      if (data['userData'] is Map) {
        final uid = (data['userData']['id']?.toString() ?? '').trim();
        if (uid.isNotEmpty) {
          _log?.call('PixivClient.checkLogin: ok userData.id=$uid');
          return true;
        }
      }

      _log?.call('PixivClient.checkLogin: userId not found -> false');
      return false;
    } catch (e) {
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

// =========================================================
// Data Models
// =========================================================

class PixivIllustBrief {
  final String id;
  final String title;
  final String thumbUrl;
  final int width;
  final int height;
  final int xRestrict;
  final List<String> tags;
  final int illustType;
  final int aiType;

  const PixivIllustBrief({
    required this.id,
    required this.title,
    required this.thumbUrl,
    required this.width,
    required this.height,
    required this.xRestrict,
    this.tags = const [],
    this.illustType = 0,
    this.aiType = 0,
  });

  bool get isUgoira => illustType == 2;
  bool get isAi => aiType == 2;

  factory PixivIllustBrief.fromJson(dynamic json) {
    if (json is! Map) return _empty();
    if (json['id'] == null) return _empty();

    return PixivIllustBrief(
      id: _parseString(json['id']),
      title: _parseString(json['title']),
      thumbUrl: _parseString(json['url']),
      width: _parseInt(json['width']),
      height: _parseInt(json['height']),
      xRestrict: _parseInt(json['xRestrict']),
      tags: _parseTags(json['tags']),
      illustType: _parseInt(json['illustType']),
      aiType: _parseInt(json['aiType']),
    );
  }

  factory PixivIllustBrief.fromMap(dynamic json) {
    if (json is! Map) return _empty();
    return PixivIllustBrief(
      id: _parseString(json['id']),
      title: _parseString(json['title']),
      thumbUrl: _parseString(json['url']),
      width: _parseInt(json['width']),
      height: _parseInt(json['height']),
      xRestrict: _parseInt(json['x_restrict']),
      tags: _parseTags(json['tags']),
      illustType: _parseInt(json['illust_type']),
      aiType: _parseInt(json['ai_type']),
    );
  }

  static PixivIllustBrief _empty() => const PixivIllustBrief(
        id: '',
        title: '',
        thumbUrl: '',
        width: 0,
        height: 0,
        xRestrict: 0,
      );

  static String _parseString(dynamic v) => v?.toString() ?? '';
  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static List<String> _parseTags(dynamic v) => (v is List) ? v.map((e) => e.toString()).toList() : [];
}

class PixivPageUrls {
  final String original;
  final String regular;
  final String small;
  final String thumbMini;

  const PixivPageUrls({
    required this.original,
    required this.regular,
    required this.small,
    required this.thumbMini,
  });

  factory PixivPageUrls.fromJson(dynamic json) {
    if (json is! Map) return _empty();
    final urls = json['urls'];
    if (urls is! Map) return _empty();

    return PixivPageUrls(
      original: urls['original']?.toString() ?? '',
      regular: urls['regular']?.toString() ?? '',
      small: urls['small']?.toString() ?? '',
      thumbMini: urls['thumb_mini']?.toString() ?? '',
    );
  }

  static PixivPageUrls _empty() => const PixivPageUrls(original: '', regular: '', small: '', thumbMini: '');
}