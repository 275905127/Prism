import 'dart:async';

import '../models/uni_wallpaper.dart';
import 'pixiv_client.dart';

/// PixivRepository：
/// - 对外只暴露 UniWallpaper（统一模型）
/// - 内部做“二段拉取”把缩略图升级成 regular/original
/// - 不碰 RuleEngine，不污染 SourceRule
class PixivRepository {
  final PixivClient _client;

  /// 控制并发：别一页 30 个 id 同时打 pages 接口把自己封了
  final int enrichConcurrency;

  PixivRepository(
    this._client, {
    this.enrichConcurrency = 6,
  });

  /// UI/图片加载用的 headers（Referer）
  Map<String, String> buildImageHeaders() => _client.buildImageHeaders();

  Future<List<UniWallpaper>> search({
  required String keyword,
  int page = 1,
  bool expandMultiPage = true, // ✅ 新增
}) async {
  final kw = keyword.trim();
  if (kw.isEmpty) return [];

  final briefs = await _client.searchArtworks(word: kw, page: page);

  final base = briefs.map((b) {
    return UniWallpaper(
      id: b.id,
      sourceId: 'pixiv',
      thumbUrl: b.thumbUrl,
      fullUrl: b.thumbUrl,
      width: b.width.toDouble(),
      height: b.height.toDouble(),
      grade: (b.xRestrict == 0) ? 'sfw' : 'nsfw',
    );
  }).toList();

  if (!expandMultiPage) {
    await _enrichFullUrlsInPlace(base);
    return base;
  }

  // ✅ 多页展开
  return await _expandMultiPage(base);
}

  Future<void> _enrichFullUrlsInPlace(List<UniWallpaper> list) async {
    if (list.isEmpty) return;

    // 简单并发池
    final sem = _Semaphore(enrichConcurrency);
    final futures = <Future<void>>[];

    for (var i = 0; i < list.length; i++) {
      final w = list[i];
      futures.add(() async {
        await sem.acquire();
        try {
          final pages = await _client.getIllustPages(w.id);
          if (pages.isEmpty) return;

          // 只取第一页做墙纸就够了（你想做多页再扩）
          final p0 = pages.first;

          final full = _pickBest(p0.original, p0.regular, p0.small, w.fullUrl);
          final thumb = _pickBest(p0.regular, p0.small, p0.thumbMini, w.thumbUrl);

          // UniWallpaper 是 const + final，不可改
          // 所以我们这里“就地替换”为新对象
          list[i] = UniWallpaper(
            id: w.id,
            sourceId: w.sourceId,
            thumbUrl: thumb,
            fullUrl: full,
            width: w.width,
            height: w.height,
            grade: w.grade,
          );
        } finally {
          sem.release();
        }
      }());
    }

    await Future.wait(futures);
  }

  String _pickBest(String a, String b, String c, String fallback) {
    if (a.trim().isNotEmpty) return a.trim();
    if (b.trim().isNotEmpty) return b.trim();
    if (c.trim().isNotEmpty) return c.trim();
    return fallback;
  }
}

class _Semaphore {
  final int _max;
  int _cur = 0;
  final List<Completer<void>> _waiters = [];

  _Semaphore(this._max);

  Future<void> acquire() {
    if (_cur < _max) {
      _cur++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future.then((_) {
      _cur++;
    });
  }

  void release() {
    _cur--;
    if (_cur < 0) _cur = 0;
    if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      if (!c.isCompleted) c.complete();
    }
  }
}