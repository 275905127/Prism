// lib/core/network/image_header_policy.dart
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class ImageHeaderPolicy {
  const ImageHeaderPolicy();

  Map<String, String>? headersFor({
    required UniWallpaper wallpaper,
    required SourceRule? rule,
  }) {
    final base = <String, String>{};

    // Merge rule headers (stringified) if present.
    final rh = rule?.headers;
    if (rh != null) {
      rh.forEach((k, v) {
        if (v == null) return;
        final key = k.toString().trim();
        if (key.isEmpty) return;
        base[key] = v.toString();
      });
    }

    final url = wallpaper.thumbUrl.isNotEmpty ? wallpaper.thumbUrl : wallpaper.fullUrl;
    final lower = url.toLowerCase();

    // Pixiv image CDN: needs Referer + UA to avoid 403.
    if (lower.contains('pximg.net')) {
      base.putIfAbsent('Referer', () => 'https://www.pixiv.net/');
      base.putIfAbsent(
        'User-Agent',
        () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
      );
      return base.isEmpty ? null : base;
    }

    // ✅ Wallhaven image CDN: often needs Referer + UA to avoid 403.
    // Common hosts:
    // - https://w.wallhaven.cc/full/...
    // - https://th.wallhaven.cc/small/...
    // - https://wallhaven.cc/...
    if (lower.contains('wallhaven.cc') || lower.contains('w.wallhaven.cc') || lower.contains('th.wallhaven.cc')) {
      base.putIfAbsent('Referer', () => 'https://wallhaven.cc/');
      base.putIfAbsent(
        'User-Agent',
        () => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36',
      );
      // 轻量兜底：部分 CDN 对 Accept 更敏感（不加也行，但加了更稳）
      base.putIfAbsent('Accept', () => 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8');
    }

    return base.isEmpty ? null : base;
  }
}