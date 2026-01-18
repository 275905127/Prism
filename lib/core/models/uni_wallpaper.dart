// lib/core/models/uni_wallpaper.dart
class UniWallpaper {
  final String id;
  final String sourceId;
  final String thumbUrl;
  final String fullUrl;
  final double width;
  final double height;
  // 🔥 新增：图片等级 (如 "nsfw", "sketchy", "sfw")
  final String? grade;

  const UniWallpaper({
    required this.id,
    this.sourceId = '',
    required this.thumbUrl,
    required this.fullUrl,
    this.width = 0,
    this.height = 0,
    this.grade, // 新增
  });

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 0.0;
    return width / height;
  }
}
