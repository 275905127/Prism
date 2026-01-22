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
        base[k.toString()] = v.toString();
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
    }

    return base.isEmpty ? null : base;
  }
}
