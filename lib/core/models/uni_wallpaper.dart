// lib/core/models/uni_wallpaper.dart

class UniWallpaper {
  final String id;
  final String thumbUrl;   // 列表图
  final String fullUrl;    // 大图
  final double width;
  final double height;
  
  // 详情页展示的元数据 (Key: 标题, Value: 内容)
  final Map<String, String> metadata;
  
  // 来源 ID (例如 "wallhaven")
  final String sourceId;

  const UniWallpaper({
    required this.id,
    required this.thumbUrl,
    required this.fullUrl,
    this.width = 0,
    this.height = 0,
    this.metadata = const {},
    required this.sourceId,
  });

  // 必须计算宽高比，否则瀑布流会跳动
  double get aspectRatio {
    if (width <= 0 || height <= 0) return 0.7; // 默认 3:4
    return width / height;
  }
}