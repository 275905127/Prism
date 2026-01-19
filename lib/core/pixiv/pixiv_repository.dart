// lib/core/pixiv/pixiv_repository.dart
//
// Pixiv 专用仓库：提供一个与 RuleEngine 类似的 fetch 接口，方便 UI 分支调用。
// ✅ 不引入 Queue
// ✅ 提供 supports(ruleId) + fetch(...)，匹配你 UI 报错里正在调用的方法名
// ✅ 输出 UniWallpaper：thumbUrl/fullUrl/width/height/id 都有
//
// 重要说明：Pixiv 没官方公开 API，本实现用 pixiv.net/ajax/search 接口。
// 需要 Referer，未登录情况下可用性取决于 Pixiv 策略/地区/频率限制。
// 这只是“能跑通 + 可扩展”的落地版本。

import 'package:dio/dio.dart';

import '../models/uni_wallpaper.dart';
import '../utils/app_log.dart';
import 'pixiv_client.dart';

class PixivRepository {
  PixivRepository({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://www.pixiv.net',
                headers: const {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Referer': 'https://www.pixiv.net/',
                  'Accept': 'application/json',
                },
                responseType: ResponseType.json,
                validateStatus: (s) => s != null && s < 500,
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  final Dio _dio;

  /// 你可以把 pixiv 规则 id 固定成这个，也可以按前缀判断
  static const String kRuleId = 'pixiv_search_ajax';

  /// UI 分支用：判断当前 rule 是否应该走 PixivRepository
  bool supports(dynamic rule) {
    try {
      final id = (rule as dynamic).id?.toString() ?? '';
      if (id == kRuleId) return true;
      // 兼容你可能写的别名
      if (id.startsWith('pixiv')) return true;
    } catch (_) {
      // ignore
    }
    return false;
  }

  /// 给 UI 用的统一入口：签名对齐 RuleEngine.fetch 的用法（page/query）
  Future<List<UniWallpaper>> fetch(
    dynamic rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams, // 预留，不用也别炸
  }) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) return const [];

    // Pixiv 的 keyword 在 path：/ajax/search/artworks/{word}
    final path = '/ajax/search/artworks/${Uri.encodeComponent(q)}';

    final params = <String, dynamic>{
      'order': 'date_d',
      'mode': 'all',
      's_mode': 's_tag',
      'p': page,
    };

    AppLog.I.add('REQ pixiv_search_ajax GET https://www.pixiv.net$path');
    AppLog.I.add('    params=$params');

    final resp = await _dio.get(path, queryParameters: params);

    AppLog.I.add(
        'RESP pixiv_search_ajax status=${resp.statusCode ?? 'N/A'} url=${resp.realUri}');
    final sc = resp.statusCode ?? 0;
    if (sc >= 400) {
      AppLog.I.add('    body=${resp.data}');
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: 'HTTP $sc',
      );
    }

    return _parse(resp.data);
  }

  List<UniWallpaper> _parse(dynamic data) {
    // 目标结构（你日志里见过）：
    // { error:false, body:{ illustManga:{ data:[{ id, url, width, height, ... }], ... } } }
    try {
      final body = (data is Map) ? data['body'] : null;
      final illustManga = (body is Map) ? body['illustManga'] : null;
      final list = (illustManga is Map) ? illustManga['data'] : null;
      if (list is! List) return const [];

      final out = <UniWallpaper>[];

      for (final item in list) {
        if (item is! Map) continue;

        final id = (item['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final width = _toDouble(item['width']);
        final height = _toDouble(item['height']);

        // Pixiv 返回的 url 通常是 square1200 / img-master（缩略）
        final thumb = (item['url'] ?? '').toString();

        // 尝试从 thumb 推导原图（i.pximg.net/img-original/...）
        // 注意：原图通常需要 Referer + 可能需要 Cookie；你当前引擎只负责给 URL，不保证能直接下原图
        final full = _deriveOriginalFromThumb(thumb) ?? thumb;

        out.add(
          UniWallpaper(
            id: id,
            sourceId: 'pixiv',
            thumbUrl: thumb,
            fullUrl: full,
            width: width,
            height: height,
          ),
        );
      }

      return out;
    } catch (e) {
      AppLog.I.add('pixiv parse error: $e');
      return const [];
    }
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  String? _deriveOriginalFromThumb(String thumb) {
    if (thumb.isEmpty) return null;

    // 常见 thumb:
    // https://i.pximg.net/c/250x250_80_a2/img-master/img/2026/01/19/18/48/32/140131153_p0_square1200.jpg
    //
    // 原图一般：
    // https://i.pximg.net/img-original/img/2026/01/19/18/48/32/140131153_p0.png (或 jpg)
    //
    // 这里做一个“尽量合理”的推导：把 /c/.../img-master/ => /img-original/
    // 并把 _square1200.jpg 去掉后缀，改成 .jpg（不保证 100%）
    try {
      final u = Uri.parse(thumb);
      if (!u.host.contains('i.pximg.net')) return null;

      final p = u.path;

      // 必须包含 img-master/img/
      final idx = p.indexOf('/img-master/img/');
      if (idx < 0) return null;

      final tail = p.substring(idx + '/img-master/'.length); // img/2026/...
      var newPath = '/img-original/$tail';

      // 去掉 _square1200 或 _master1200 等
      newPath = newPath
          .replaceAll('_square1200', '')
          .replaceAll('_master1200', '')
          .replaceAll('_custom1200', '');

      // 把 jpg/png 后缀“先保留”，因为不确定原图格式
      // 这里不强改扩展名，只做路径替换
      return u.replace(path: newPath, query: '').toString();
    } catch (_) {
      return null;
    }
  }
}