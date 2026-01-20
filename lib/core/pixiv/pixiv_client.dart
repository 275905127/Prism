// lib/core/pixiv/pixiv_client.dart
import 'package:dio/dio.dart';

/// Pixiv Ajax API Client（无需 key）
///
/// - 搜索：/ajax/search/artworks/{word}?p=1...
/// - 取大图/原图：/ajax/illust/{id}/pages
///
/// 注意：
/// 1) i.pximg.net 图片通常要求 Referer: https://www.pixiv.net/
/// 2) 部分内容可能需要登录 Cookie（可选）
/// 3) User-Agent 必须与 Cookie 获取端的浏览器一致，否则会被判定为劫持
class PixivClient {
  final Dio _dio;
  String? _cookie;
  
  // 🔥 默认 UA，但会被 updateConfig 覆盖
  String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  PixivClient({
    Dio? dio,
    String? cookie,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie {
    // 初始化 Headers
    _updateHeaders();
    
    _dio.options = _dio.options.copyWith(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
    );
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  /// 🔥 核心方法：允许外部(Repo)同步更新 Cookie 和 UA
  void updateConfig({String? cookie, String? userAgent}) {
    if (cookie != null) _cookie = cookie;
    if (userAgent != null && userAgent.isNotEmpty) _userAgent = userAgent;
    _updateHeaders();
  }

  /// 单独设置 Cookie (兼容旧接口)
  void setCookie(String? cookie) {
    _cookie = cookie;
    _updateHeaders();
  }

  /// 统一刷新 Dio Headers
  void _updateHeaders() {
    _dio.options.headers = {
      'User-Agent': _userAgent, // 🔥 动态 UA
      'Referer': 'https://www.pixiv.net/',
      'Accept': 'application/json',
      if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
    };
  }

  /// 给 i.pximg.net 图片加载用（CachedNetworkImage / Dio 下载）
  /// 🔥 必须确保这里的 UA 和 Cookie 与请求 API 时的一致
  Map<String, String> buildImageHeaders() {
    final h = <String, String>{
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
    };
    final c = _cookie?.trim() ?? '';
    if (c.isNotEmpty) h['Cookie'] = c;
    return h;
  }

  /// 搜索：返回 illust id + 搜索页给的缩略图
  Future<List<PixivIllustBrief>> searchArtworks({
    required String word,
    int page = 1,
    String order = 'date_d',
    String mode = 'all',
    String sMode = 's_tag',
  }) async {
    final w = word.trim();
    if (w.isEmpty) return [];

    final path = '/ajax/search/artworks/${Uri.encodeComponent(w)}';

    // Headers 已经在 _updateHeaders 中设置到了 _dio.options，此处无需重复设置
    final resp = await _dio.get(
      path,
      queryParameters: {
        'order': order,
        'mode': mode,
        's_mode': sMode,
        'p': page,
      },
    );

    final sc = resp.statusCode ?? 0;
    if (sc >= 400) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: 'HTTP $sc',
      );
    }

    final data = resp.data;
    if (data is! Map) return [];

    final body = data['body'];
    if (body is! Map) return [];

    final illustManga = body['illustManga'];
    if (illustManga is! Map) return [];

    final list = illustManga['data'];
    if (list is! List) return [];

    final out = <PixivIllustBrief>[];
    for (final it in list) {
      if (it is! Map) continue;

      final id = (it['id'] ?? '').toString();
      if (id.isEmpty) continue;

      out.add(
        PixivIllustBrief(
          id: id,
          title: (it['title'] ?? '').toString(),
          thumbUrl: (it['url'] ?? '').toString(),
          width: _toInt(it['width']),
          height: _toInt(it['height']),
          xRestrict: _toInt(it['xRestrict']),
        ),
      );
    }
    return out;
  }

  /// 获取作品所有页 URL（含 original / regular / small）
  Future<List<PixivPageUrls>> getIllustPages(String illustId) async {
    final id = illustId.trim();
    if (id.isEmpty) return [];

    final resp = await _dio.get('/ajax/illust/$id/pages');

    final sc = resp.statusCode ?? 0;
    if (sc >= 400) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: 'HTTP $sc',
      );
    }

    final data = resp.data;
    if (data is! Map) return [];

    final body = data['body'];
    if (body is! List) return [];

    final out = <PixivPageUrls>[];
    for (final it in body) {
      if (it is! Map) continue;
      final urls = it['urls'];
      if (urls is! Map) continue;

      out.add(
        PixivPageUrls(
          original: (urls['original'] ?? '').toString(),
          regular: (urls['regular'] ?? '').toString(),
          small: (urls['small'] ?? '').toString(),
          thumbMini: (urls['thumb_mini'] ?? '').toString(),
        ),
      );
    }
    return out;
  }
  
  // 新增：获取用户作品（兼容之前提到的扩展）
  Future<List<PixivIllustBrief>> getUserArtworks({
    required String userId,
    int page = 1,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return [];

    // 注意：Touch API 可能需要特殊的 UA，但通常 Desktop UA 也能通过
    final resp = await _dio.get(
      '/touch/ajax/user/illusts',
      queryParameters: {'user_id': uid, 'p': page},
    );

    final data = resp.data;
    if (data is! Map) return [];
    final body = data['body'];
    if (body is! Map) return [];
    final illusts = body['illusts'];
    if (illusts is! List) return [];

    final out = <PixivIllustBrief>[];
    for (final it in illusts) {
      if (it is! Map) continue;
      out.add(PixivIllustBrief(
        id: (it['id'] ?? '').toString(),
        title: (it['title'] ?? '').toString(),
        thumbUrl: (it['url'] ?? '').toString(),
        width: _toInt(it['width']),
        height: _toInt(it['height']),
        xRestrict: _toInt(it['x_restrict']),
      ));
    }
    return out;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class PixivIllustBrief {
  final String id;
  final String title;
  final String thumbUrl;
  final int width;
  final int height;
  final int xRestrict;

  const PixivIllustBrief({
    required this.id,
    required this.title,
    required this.thumbUrl,
    required this.width,
    required this.height,
    required this.xRestrict,
  });
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
}
