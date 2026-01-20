// lib/core/models/uni_wallpaper.dart
class UniWallpaper {
  final String id;
  final String sourceId;
  final String thumbUrl;
  final String fullUrl;
  final double width;
  final double height;
  final String? grade; // "nsfw", "sketchy", "sfw"
  
  // 🔥 新增：功能性标识
  final bool isUgoira; // 是否为动图
  final bool isAi;     // 是否为 AI 生成

  const UniWallpaper({
    required this.id,
    this.sourceId = '',
    required this.thumbUrl,
    required this.fullUrl,
    this.width = 0,
    this.height = 0,
    this.grade,
    this.isUgoira = false, // default false
    this.isAi = false,     // default false
  });

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 0.0;
    return width / height;
  }
}
