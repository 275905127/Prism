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
  final List<String> tags;

  // 🔥 新增：详情页元数据字段 (适配 Wallhaven/Pixiv 详细信息)
  final String uploader;    // 上传者
  final String views;       // 浏览量 (存字符串，方便处理 "1.2k" 这种格式)
  final String favorites;   // 收藏量
  final String fileSize;    // 文件大小 (如 "5.2 MB")
  final String createdAt;   // 上传时间 (如 "2026-01-20")
  final String mimeType;    // 文件类型 (如 "image/png")

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
    this.tags = const [],
    
    // 🔥 给默认值，防止旧的解析代码报错
    this.uploader = 'Unknown User',
    this.views = '',
    this.favorites = '',
    this.fileSize = '',
    this.createdAt = '',
    this.mimeType = '',
  });

  // 辅助属性：计算宽高比
  double get aspectRatio {
    if (width > 0 && height > 0) return width / height;
    return 1.0;
  }
}
