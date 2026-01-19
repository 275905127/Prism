import 'package:dio/dio.dart';

/// Pixiv Ajax API Client（无需 key）
///
/// - 搜索：/ajax/search/artworks/{word}?p=1...
/// - 取大图/原图：/ajax/illust/{id}/pages
///
/// 注意：
/// 1) i.pximg.net 图片通常要求 Referer: https://www.pixiv.net/
/// 2) 部分内容可能需要登录 Cookie（可选）
/// 3) 这里只负责请求 Pixiv Ajax，不掺进 RuleEngine
class PixivClient {
  final Dio _dio;
  String? _cookie;

  PixivClient({
    Dio? dio,
    String? cookie,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie {
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

  /// 给 i.pximg.net 图片加载用（CachedNetworkImage / Dio 下载）
  Map<String, String> buildImageHeaders() {
    final h = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Referer': 'https://www.pixiv.net/',
    };
    final c = _cookie?.trim() ?? '';
    if (c.isNotEmpty) h['Cookie'] = c;
    return h;
  }

  static Map<String, dynamic> _baseApiHeaders({String? cookie}) {
    final h = <String, dynamic>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      'Referer': 'https://www.pixiv.net/',
      'Accept': 'application/json',
    };
    final c = cookie?.trim() ?? '';
    if (c.isNotEmpty) h['Cookie'] = c;
    return h;
  }

  /// 搜索：返回 illust id + 搜索页给的缩略图（square1200 / img-master）
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