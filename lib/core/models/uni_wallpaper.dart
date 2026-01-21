// lib/core/models/uni_wallpaper.dart
class UniWallpaper {
  final String id;
  final String sourceId;
  final String thumbUrl;
  final String fullUrl;
  final double width;
  final double height;
  final String? grade; // 'safe', 'sketchy', 'nsfw'
  final bool isUgoira;
  final bool isAi;
  final List<String> tags; // 🔥 新增：标签列表

  const UniWallpaper({
    required this.id,
    required this.sourceId,
    required this.thumbUrl,
    required this.fullUrl,
    required this.width,
    required this.height,
    this.grade,
    this.isUgoira = false,
    this.isAi = false,
    this.tags = const [], // 🔥 默认为空列表
  });

  // 如果你有 fromJson/toJson 也需要对应修改，这里为了不破坏你现有的逻辑，
  // 假设你的转换逻辑是在 Repository 层手动做的（如之前的 PixivRepository）。
  
  // 辅助属性：计算宽高比
  double get aspectRatio {
    if (width > 0 && height > 0) return width / height;
    return 1.0;
  }
}
