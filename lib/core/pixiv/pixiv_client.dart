// lib/core/pixiv/pixiv_client.dart
import 'package:dio/dio.dart';

class PixivClient {
  final Dio _dio;
  String? _cookie;

  /// 全局统一的 Mobile UA (Android Chrome)
  static const String kMobileUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  String _userAgent = kMobileUserAgent;

  /// 普通日志（关键业务）
  final void Function(String msg)? _log;

  /// Debug 日志（高频）
  final void Function(String msg)? _debug;

  PixivClient({
    Dio? dio,
    String? cookie,
    void Function(String msg)? logger,
    void Function(String msg)? debugLogger,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie,
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
    _installDebugInterceptors();
    _refreshHeaders();
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  void updateConfig({String? cookie, String? userAgent}) {
    bool changed = false;
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
      _debug?.call(
        'PixivClient.updateConfig changed: hasCookie=$hasCookie '
        'cookieLen=${(_cookie ?? '').length} uaLen=${_userAgent.length}',
      );
    }
  }

  void setCookie(String? cookie) {
    updateConfig(cookie: cookie);
  }

  /// ✅ 安全设置 Header，避免 _cookie 在并发/时序问题下为空时解包崩溃
  void _refreshHeaders() {
    final headers = <String, dynamic>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };

    final c = _cookie;
    if (c != null && c.trim().isNotEmpty) {
      headers['Cookie'] = c;
    }

    _dio.options.headers = headers;

    _debug?.call(
      'PixivClient.refreshHeaders: hasCookie=$hasCookie headers=${headers.keys.toList()}',
    );
  }

  Map<String, String> buildImageHeaders() {
    final out = <String, String>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
    };

    final c = _cookie;
    if (c != null && c.trim().isNotEmpty) {
      out['Cookie'] = c;
    }

    return out;
  }

  void _installDebugInterceptors() {
    _dio.interceptors.removeWhere((i) => i is InterceptorsWrapper);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final hasC = (options.headers['Cookie']?.toString().trim().isNotEmpty ?? false);
          _debug?.call(
            'PixivClient REQ ${options.method} ${options.baseUrl}${options.path} hasCookie=$hasC',
          );
          handler.next(options);
        },
        onResponse: (resp, handler) {
          _debug?.call(
            'PixivClient RESP ${resp.statusCode} ${resp.requestOptions.path}',
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
      _log?.call('PixivClient.checkLogin: no cookie');
      return false;
    }

    try {
      final resp = await _dio.get('/ajax/user/self');
      final sc = resp.statusCode ?? 0;

      if (sc >= 400) {
        _log?.call('PixivClient.checkLogin: status=$sc');
        return false;
      }

      final data = resp.data;
      if (data is! Map) {
        _log?.call('PixivClient.checkLogin: invalid response');
        return false;
      }

      if (data['body'] is Map) {
        final uid = data['body']['userId']?.toString() ?? '';
        if (uid.trim().isNotEmpty) {
          _log?.call('PixivClient.checkLogin: ok userId=$uid');
          return true;
        }
      }

      if (data['userData'] is Map) {
        final uid = data['userData']['id']?.toString() ?? '';
        if (uid.trim().isNotEmpty) {
          _log?.call('PixivClient.checkLogin: ok userData.id=$uid');
          return true;
        }
      }

      _log?.call('PixivClient.checkLogin: userId not found');
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

  /// ✅ 详情补全：用于“阶段 2”补全 uploader/tags/view/bookmark/createDate
  Future<PixivIllustDetail?> getIllustDetail(String illustId) async {
    if (illustId.trim().isEmpty) return null;
    try {
      final resp = await _dio.get('/ajax/illust/$illustId');
      if ((resp.statusCode ?? 0) >= 400) return null;
      final data = resp.data;
      if (data is! Map) return null;
      final body = data['body'];
      if (body is! Map) return null;
      final detail = PixivIllustDetail.fromBody(body);
      return detail.id.isEmpty ? null : detail;
    } catch (e) {
      _log?.call('PixivClient.getIllustDetail exception: $e');
      return null;
    }
  }

  /// ✅ user: 通配：用户名 -> userId（取第一个匹配）
  ///
  /// 说明：Pixiv 的 users 搜索返回结构可能随时间变化，因此这里用“多形态解析”：
  /// - body.users / body.user / body.userPreview / body.items 等都尝试一下
  Future<String?> resolveUserIdByName(String userName) async {
    final q = userName.trim();
    if (q.isEmpty) return null;

    try {
      // 常见路径：/ajax/search/users/<word>?word=<word>&p=1
      final resp = await _dio.get(
        '/ajax/search/users/${Uri.encodeComponent(q)}',
        queryParameters: {'word': q, 'p': 1},
      );
      if ((resp.statusCode ?? 0) >= 400) return null;

      final data = resp.data;
      if (data is! Map) return null;
      final body = data['body'];
      if (body is! Map) return null;

      dynamic candidates = body['users'] ?? body['user'] ?? body['items'] ?? body['userPreviews'];
      if (candidates is Map && candidates['data'] is List) {
        candidates = candidates['data'];
      }

      if (candidates is! List || candidates.isEmpty) return null;

      for (final c in candidates) {
        if (c is! Map) continue;
        final id = (c['userId'] ?? c['id'] ?? c['user_id'])?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
      return null;
    } catch (e) {
      _log?.call('PixivClient.resolveUserIdByName exception: $e');
      return null;
    }
  }
}

// =========================================================
// Data Models
// =========================================================

class PixivIllustDetail {
  final String id;
  final String userId;
  final String userName;
  final List<String> tags;
  final int viewCount;
  final int bookmarkCount;
  final String createDate; // ISO string from pixiv
  final int width;
  final int height;
  final int xRestrict;
  final int illustType;
  final int aiType;

  const PixivIllustDetail({
    required this.id,
    required this.userId,
    required this.userName,
    required this.tags,
    required this.viewCount,
    required this.bookmarkCount,
    required this.createDate,
    required this.width,
    required this.height,
    required this.xRestrict,
    required this.illustType,
    required this.aiType,
  });

  bool get isUgoira => illustType == 2;
  bool get isAi => aiType == 2;

  factory PixivIllustDetail.fromBody(Map body) {
    final id = (body['illustId'] ?? body['id'])?.toString() ?? '';
    final userId = (body['userId'] ?? body['user_id'])?.toString() ?? '';
    final userName = (body['userName'] ?? body['user_name'])?.toString() ?? '';

    final viewCount = _parseInt(body['viewCount'] ?? body['view_count']);
    final bookmarkCount = _parseInt(body['bookmarkCount'] ?? body['bookmark_count']);

    final createDate = (body['createDate'] ?? body['uploadDate'] ?? body['create_date'] ?? '')?.toString() ?? '';

    final width = _parseInt(body['width']);
    final height = _parseInt(body['height']);
    final xRestrict = _parseInt(body['xRestrict'] ?? body['x_restrict']);
    final illustType = _parseInt(body['illustType'] ?? body['illust_type']);
    final aiType = _parseInt(body['aiType'] ?? body['ai_type']);

    final tags = _parseTagsFromDetail(body['tags']);

    return PixivIllustDetail(
      id: id,
      userId: userId,
      userName: userName,
      tags: tags,
      viewCount: viewCount,
      bookmarkCount: bookmarkCount,
      createDate: createDate,
      width: width,
      height: height,
      xRestrict: xRestrict,
      illustType: illustType,
      aiType: aiType,
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static List<String> _parseTagsFromDetail(dynamic tagsNode) {
    // 常见结构： { tags: [ { tag: "xxx", ...}, ...] }
    // 或： { tags: { tags: [ { tag: "xxx"} ] } }
    // 或：直接是 List<String>
    if (tagsNode == null) return const [];

    dynamic node = tagsNode;
    if (node is Map) {
      node = node['tags'] ?? node['data'] ?? node['items'];
    }
    if (node is List) {
      final out = <String>[];
      for (final e in node) {
        if (e is String) {
          final s = e.trim();
          if (s.isNotEmpty) out.add(s);
          continue;
        }
        if (e is Map) {
          final s = (e['tag'] ?? e['name'] ?? e['value'])?.toString().trim() ?? '';
          if (s.isNotEmpty) out.add(s);
        }
      }
      return out;
    }
    return const [];
  }
}

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

  // ✅ 新增：用于详情页/相似搜索的关键字段（优先从列表阶段拿）
  final String userId;
  final String userName;
  final int viewCount;
  final int bookmarkCount;
  final String createDate;

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
    this.userId = '',
    this.userName = '',
    this.viewCount = 0,
    this.bookmarkCount = 0,
    this.createDate = '',
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

      // search/artworks 里经常存在（但不保证）
      userId: _parseString(json['userId'] ?? json['user_id']),
      userName: _parseString(json['userName'] ?? json['user_name']),
      viewCount: _parseInt(json['viewCount'] ?? json['view_count']),
      bookmarkCount: _parseInt(json['bookmarkCount'] ?? json['bookmark_count']),
      createDate: _parseString(json['createDate'] ?? json['create_date'] ?? json['uploadDate']),
    );
  }

  factory PixivIllustBrief.fromMap(dynamic json) {
    if (json is! Map) return _empty();

    // touch/ajax/ranking、touch/ajax/user/illusts 返回字段常用下划线
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

      userId: _parseString(json['user_id'] ?? json['userId']),
      userName: _parseString(json['user_name'] ?? json['userName']),
      viewCount: _parseInt(json['view_count'] ?? json['viewCount']),
      bookmarkCount: _parseInt(json['bookmark_count'] ?? json['bookmarkCount']),
      createDate: _parseString(json['create_date'] ?? json['createDate'] ?? json['upload_date'] ?? json['uploadDate']),
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

  static List<String> _parseTags(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }
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

  static PixivPageUrls _empty() => const PixivPageUrls(
        original: '',
        regular: '',
        small: '',
        thumbMini: '',
      );
}