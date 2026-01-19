import 'dart:async';

import '../models/uni_wallpaper.dart';
import '../utils/app_log.dart';
import 'pixiv_client.dart';

/// Pixiv 专用仓库
/// ❗不走 RuleEngine
/// ❗不污染通用架构
/// ❗Pixiv 的反爬、Cookie、多页都在这里兜住
class PixivRepository {
  final PixivClient _client;

  /// 并发控制（防止被 Pixiv 封）
  final int enrichConcurrency;

  PixivRepository(
    this._client, {
    this.enrichConcurrency = 4,
  });

  // ------------------------------------------------------------
  // 对外入口
  // ------------------------------------------------------------

  /// 搜索 Pixiv 作品
  ///
  /// - keyword：搜索词（必填）
  /// - page：Pixiv 的 p=1,2,3...
  /// - expandMultiPage：是否展开多页作品
  ///
  /// 返回：已经可直接用于 UI 的 UniWallpaper 列表
  Future<List<UniWallpaper>> search({
    required String keyword,
    int page = 1,
    bool expandMultiPage = true,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];

    AppLog.I.add('PIXIV search "$kw" page=$page');

    // 1️⃣ 拉搜索结果（只有缩略信息）
    final briefs = await _client.searchArtworks(
      word: kw,
      page: page,
    );

    if (briefs.isEmpty) return [];

    // 2️⃣ 先生成“基础壁纸”（即使失败也能显示）
    final base = briefs.map((b) {
      return UniWallpaper(
        id: b.id,
        sourceId: 'pixiv',
        thumbUrl: b.thumbUrl,
        fullUrl: b.thumbUrl, // 先占位
        width: b.width.toDouble(),
        height: b.height.toDouble(),
        grade: (b.xRestrict == 0) ? 'sfw' : 'nsfw',
      );
    }).toList();

    // 3️⃣ 如果不展开多页，只补 fullUrl
    if (!expandMultiPage) {
      await _enrichFullUrlsInPlace(base);
      return base;
    }

    // 4️⃣ 展开多页（p0 / p1 / p2…）
    return await _expandMultiPage(base);
  }

  // ------------------------------------------------------------
  // 多页展开
  // ------------------------------------------------------------

  Future<List<UniWallpaper>> _expandMultiPage(
    List<UniWallpaper> base,
  ) async {
    final out = <UniWallpaper>[];
    final sem = _Semaphore(enrichConcurrency);
    final futures = <Future<void>>[];

    for (final w in base) {
      futures.add(() async {
        await sem.acquire();
        try {
          final pages = await _client.getIllustPages(w.id);
          if (pages.isEmpty) return;

          for (var i = 0; i < pages.length; i++) {
            final p = pages[i];

            final full = _pickBest(
              p.original,
              p.regular,
              p.small,
              w.fullUrl,
            );

            final thumb = _pickBest(
              p.regular,
              p.small,
              p.thumbMini,
              w.thumbUrl,
            );

            out.add(
              UniWallpaper(
                id: '${w.id}#$i', // ✅ 稳定多页 ID
                sourceId: w.sourceId,
                thumbUrl: thumb,
                fullUrl: full,
                width: w.width,
                height: w.height,
                grade: w.grade,
              ),
            );
          }
        } catch (e) {
          AppLog.I.add('PIXIV expand failed id=${w.id} err=$e');
        } finally {
          sem.release();
        }
      }());
    }

    await Future.wait(futures);
    return out;
  }

  // ------------------------------------------------------------
  // 单页补全（不展开多页时）
  // ------------------------------------------------------------

  Future<void> _enrichFullUrlsInPlace(
    List<UniWallpaper> list,
  ) async {
    final sem = _Semaphore(enrichConcurrency);
    final futures = <Future<void>>[];

    for (final w in list) {
      futures.add(() async {
        await sem.acquire();
        try {
          final pages = await _client.getIllustPages(w.id);
          if (pages.isEmpty) return;

          final p = pages.first;
          final full = _pickBest(
            p.original,
            p.regular,
            p.small,
            w.fullUrl,
          );

          if (full.isNotEmpty) {
            w.fullUrl = full;
          }
        } catch (_) {
          // 忽略失败，保留 thumb
        } finally {
          sem.release();
        }
      }());
    }

    await Future.wait(futures);
  }

  // ------------------------------------------------------------
  // URL 选择策略
  // ------------------------------------------------------------

  String _pickBest(
    String? a,
    String? b,
    String? c,
    String fallback,
  ) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    if (c != null && c.isNotEmpty) return c;
    return fallback;
  }

  // ------------------------------------------------------------
  // 给 UI 用的图片请求头
  // ------------------------------------------------------------

  /// Pixiv 图片必须带 Referer
  /// ❗不要混进 RuleEngine
  Map<String, String> buildImageHeaders() {
    return _client.buildImageHeaders();
  }
}

// ------------------------------------------------------------
// 简单信号量（避免额外依赖）
// ------------------------------------------------------------

class _Semaphore {
  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _queue = Queue();

  _Semaphore(this._max);

  Future<void> acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _current--;
    }
  }
}