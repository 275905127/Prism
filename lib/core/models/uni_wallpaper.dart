// lib/core/models/uni_wallpaper.dart
class UniWallpaper {
  final String id;
  final String sourceId;
  final String thumbUrl;
  final String fullUrl;
  final double width;
  final double height;

  const UniWallpaper({
    required this.id,
    this.sourceId = '',
    required this.thumbUrl,
    required this.fullUrl,
    this.width = 0,
    this.height = 0,
  });

  // 🔥 核心修改：如果宽或高是 0，返回 0，代表“未知比例”
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 0.0;
    return width / height;
  }
}
