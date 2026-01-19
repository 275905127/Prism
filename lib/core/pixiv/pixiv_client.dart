import 'package:dio/dio.dart';

/// Pixiv Ajax API Client（无需 key）
/// - 搜索：/ajax/search/artworks/{word}?p=1...
/// - 取原图/大图：/ajax/illust/{id}/pages
///
/// 注意：
/// 1) i.pximg.net 图片通常要求 Referer: https://www.pixiv.net/
/// 2) 部分内容可能需要登录 Cookie（可选，不强制）
/// 3) 这里是“平台 SDK”，不掺进 RuleEngine
class PixivClient {
  final Dio _dio;
  String? _cookie;

  PixivClient({
    Dio? dio,
    String? cookie,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie {
    // 你也可以在外面传 Dio 并统一代理/超时
    _dio.options = _dio.options.copyWith(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
      headers: _baseApiHeaders(cookie: cookie),
    );
  }

  void setCookie(String? cookie) {
    _cookie = cookie;
    _dio.options.headers = _baseApiHeaders(cookie: cookie);
  }

  /// 给图片加载/下载用（CachedNetworkImage / Dio 下载原图）
  /// - Pixiv 图片 CDN 基本需要 Referer
  Map<String, String> buildImageHeaders() {
    final h = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Referer': 'https://www.pixiv.net/',
    };
    if (_cookie != null && _cookie!.trim().isNotEmpty) {
      h['Cookie'] = _cookie!.trim();
    }
    return h;
  }

  static Map<String, dynamic> _baseApiHeaders({String? cookie}) {
    final h = <String, dynamic>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Referer': 'https://www.pixiv.net/',
      'Accept': 'application/json',
    };
    if (cookie != null && cookie.trim().isNotEmpty) {
      h['Cookie'] = cookie.trim();
    }
    return h;
  }

  /// 搜索：返回 illust id + 搜索页给的缩略图（square1200）
  /// 你日志里验证过这个接口 200：
  /// GET /ajax/search/artworks/{word}?order=date_d&mode=all&s_mode=s_tag&p=1
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

    final resp = await _dio.get(
      path,
      queryParameters: {
        'order': order,
        'mode': mode,
        's_mode': sMode,
        'p': page,
      },
      options: Options(headers: _baseApiHeaders(cookie: _cookie)),
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

    // { error: false, body: { illustManga: { data: [...] } } }
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
          // 这是搜索页给的缩略图（square1200）
          thumbUrl: (it['url'] ?? '').toString(),
          width: _toInt(it['width']),
          height: _toInt(it['height']),
          xRestrict: _toInt(it['xRestrict']),
        ),
      );
    }
    return out;
  }

  /// 获取某个作品的所有页图 URL（最关键：original / regular / small）
  /// GET /ajax/illust/{id}/pages
  Future<List<PixivPageUrls>> getIllustPages(String illustId) async {
    final id = illustId.trim();
    if (id.isEmpty) return [];

    final resp = await _dio.get(
      '/ajax/illust/$id/pages',
      options: Options(headers: _baseApiHeaders(cookie: _cookie)),
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

  /// 0=全年龄，1/2=限制（大概）
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