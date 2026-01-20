// lib/core/pixiv/pixiv_client.dart
import 'package:dio/dio.dart';

class PixivClient {
  final Dio _dio;
  String? _cookie;
  
  // 默认使用 PC 端 UA
  String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final void Function(String msg)? _log;

  PixivClient({
    Dio? dio,
    String? cookie,
    void Function(String msg)? logger,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie,
        _log = logger {
    
    // 基础配置
    _dio.options = _dio.options.copyWith(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status < 500, 
    );
    
    _refreshHeaders();
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  /// 更新配置（Cookie 或 UA）
  void updateConfig({String? cookie, String? userAgent}) {
    bool changed = false;
    if (cookie != null) {
      _cookie = cookie;
      changed = true;
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      _userAgent = userAgent;
      changed = true;
    }
    if (changed) _refreshHeaders();
  }

  /// 🔥 修复点：加回这个方法以兼容 PixivRepository
  void setCookie(String? cookie) {
    updateConfig(cookie: cookie);
  }

  void _refreshHeaders() {
    _dio.options.headers = {
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      if (hasCookie) 'Cookie': _cookie!,
    };
  }

  Map<String, String> buildImageHeaders() {
    return {
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      if (hasCookie) 'Cookie': _cookie!,
    };
  }

  // =========================================================
  // API 方法
  // =========================================================

  Future<bool> checkLogin() async {
    if (!hasCookie) return false;

    try {
      final resp = await _dio.get('/ajax/user/self');
      if ((resp.statusCode ?? 0) >= 400) return false;

      final data = resp.data;
      if (data is! Map) return false;

      // 1. Desktop
      if (data['body'] is Map) {
        final uid = data['body']['userId']?.toString() ?? '';
        if (uid.isNotEmpty) return true;
      }

      // 2. Mobile
      if (data['userData'] is Map) {
        final uid = data['userData']['id']?.toString() ?? '';
        if (uid.isNotEmpty) return true;
      }
      
      return false;
    } catch (e) {
      _log?.call('CheckLogin Error: $e');
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

      final body = resp.data['body'];
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
      _log?.call('Search Error: $e');
      return [];
    }
  }

  Future<List<PixivPageUrls>> getIllustPages(String illustId) async {
    if (illustId.isEmpty) return [];
    try {
      final resp = await _dio.get('/ajax/illust/$illustId/pages');
      if ((resp.statusCode ?? 0) >= 400) return [];
      
      final body = resp.data['body'];
      if (body is! List) return [];

      return body.map((e) => PixivPageUrls.fromJson(e)).toList();
    } catch (e) {
      _log?.call('GetPages Error: $e');
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
      _log?.call('UserArtworks Error: $e');
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

  const PixivIllustBrief({
    required this.id,
    required this.title,
    required this.thumbUrl,
    required this.width,
    required this.height,
    required this.xRestrict,
    this.tags = const [],
  });

  factory PixivIllustBrief.fromJson(dynamic json) {
    if (json is! Map) return _empty();
    if (json['id'] == null) return _empty(); // Filter ads

    return PixivIllustBrief(
      id: _parseString(json['id']),
      title: _parseString(json['title']),
      thumbUrl: _parseString(json['url']),
      width: _parseInt(json['width']),
      height: _parseInt(json['height']),
      xRestrict: _parseInt(json['xRestrict']),
      tags: _parseTags(json['tags']),
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
    );
  }

  static PixivIllustBrief _empty() => const PixivIllustBrief(
      id: '', title: '', thumbUrl: '', width: 0, height: 0, xRestrict: 0);

  static String _parseString(dynamic v) => v?.toString() ?? '';
  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
  static List<String> _parseTags(dynamic v) => 
      (v is List) ? v.map((e) => e.toString()).toList() : [];
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

  static PixivPageUrls _empty() => 
      const PixivPageUrls(original: '', regular: '', small: '', thumbMini: '');
}
