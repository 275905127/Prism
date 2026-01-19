import 'dart:async';

import 'package:dio/dio.dart';

import '../models/uni_wallpaper.dart';
import '../utils/app_log.dart';
import 'pixiv_client.dart';

/// Pixiv 专用仓库（不走 RuleEngine）
///
/// UI 只需要：
/// - if (_pixivRepo.supports(rule)) => _pixivRepo.fetch(...)
class PixivRepository {
  PixivRepository({
    Dio? dio,
    String? cookie,
    PixivClient? client,
  })  : _dio = dio ??
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
                receiveTimeout: const Duration(seconds: 15),
              ),
            ),
        _client = client ?? PixivClient(dio: dio, cookie: cookie);

  final Dio _dio;
  final PixivClient _client;

  static const String kRuleId = 'pixiv_search_ajax';

  bool supports(dynamic rule) {
    try {
      final id = (rule as dynamic).id?.toString() ?? '';
      if (id == kRuleId) return true;
      if (id.startsWith('pixiv')) return true;
    } catch (_) {}
    return false;
  }

  Map<String, String> buildImageHeaders() => _client.buildImageHeaders();

  Future<List<UniWallpaper>> fetch(
    dynamic rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final q = (query ?? '').trim();
    if (q.isEmpty) return const [];

    // 1) 先搜（快速拿到缩略图 + id）
    AppLog.I.add('REQ pixiv_search_ajax q="$q" page=$page');
    final briefs = await _client.searchArtworks(word: q, page: page);
    AppLog.I.add('RESP pixiv_search_ajax count=${briefs.length}');

    if (briefs.isEmpty) return const [];

    // 2) 再补 fullUrl（regular/original），避免“全是缩略图”
    //    不要傻逼到每张都串行：用并发池。
    final enriched = await _enrichWithPages(briefs, concurrency: 4);

    // 3) 转 UniWallpaper
    final out = <UniWallpaper>[];
    for (final e in enriched) {
      out.add(
        UniWallpaper(
          id: e.id,
          sourceId: 'pixiv',
          thumbUrl: e.thumbUrl,
          fullUrl: e.fullUrl,
          width: e.width.toDouble(),
          height: e.height.toDouble(),
          grade: e.grade,
        ),
      );
    }
    return out;
  }

  Future<List<_PixivEnriched>> _enrichWithPages(
    List<PixivIllustBrief> briefs, {
    int concurrency = 4,
  }) async {
    final results = List<_PixivEnriched>.filled(briefs.length, _PixivEnriched.empty(), growable: false);

    int i = 0;
    Future<void> worker() async {
      while (true) {
        final idx = i;
        i++;
        if (idx >= briefs.length) return;

        final b = briefs[idx];

        // 默认：先用 thumb 推一个 full（兜底）
        var full = _deriveOriginalFromThumb(b.thumbUrl) ?? b.thumbUrl;
        var grade = _gradeFromRestrict(b.xRestrict);

        try {
          final pages = await _client.getIllustPages(b.id);
          if (pages.isNotEmpty) {
            // 优先 regular（更稳定），original 更可能格式/权限坑
            final p0 = pages.first;
            final regular = p0.regular.trim();
            final original = p0.original.trim();

            if (regular.isNotEmpty) full = regular;
            else if (original.isNotEmpty) full = original;
          }
        } catch (e) {
          // 不要炸主流程，记录一下就行
          AppLog.I.add('pixiv pages fail id=${b.id} err=$e');
        }

        results[idx] = _PixivEnriched(
          id: b.id,
          thumbUrl: b.thumbUrl,
          fullUrl: full,
          width: b.width,
          height: b.height,
          grade: grade,
        );
      }
    }

    final workers = List.generate(concurrency, (_) => worker());
    await Future.wait(workers);
    return results.where((e) => e.id.isNotEmpty).toList();
  }

  String? _gradeFromRestrict(int xRestrict) {
    if (xRestrict <= 0) return null;
    // 粗暴点：>0 就当 sketchy/nsfw
    return xRestrict >= 2 ? 'nsfw' : 'sketchy';
  }

  String? _deriveOriginalFromThumb(String thumb) {
    if (thumb.isEmpty) return null;

    // thumb:
    // https://i.pximg.net/c/250x250_80_a2/img-master/img/2026/01/19/18/48/32/140131153_p0_square1200.jpg
    try {
      final u = Uri.parse(thumb);
      if (!u.host.contains('i.pximg.net')) return null;

      final p = u.path;
      final idx = p.indexOf('/img-master/img/');
      if (idx < 0) return null;

      final tail = p.substring(idx + '/img-master/'.length); // img/2026/...
      var newPath = '/img-original/$tail';

      newPath = newPath
          .replaceAll('_square1200', '')
          .replaceAll('_master1200', '')
          .replaceAll('_custom1200', '');

      // 不强改扩展名（png/jpg 不确定）
      return u.replace(path: newPath, query: '').toString();
    } catch (_) {
      return null;
    }
  }
}

class _PixivEnriched {
  final String id;
  final String thumbUrl;
  final String fullUrl;
  final int width;
  final int height;
  final String? grade;

  const _PixivEnriched({
    required this.id,
    required this.thumbUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
    required this.grade,
  });

  factory _PixivEnriched.empty() => const _PixivEnriched(
        id: '',
        thumbUrl: '',
        fullUrl: '',
        width: 0,
        height: 0,
        grade: null,
      );
}