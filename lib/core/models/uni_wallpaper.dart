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

  // 🔥 详情页元数据字段（可由列表解析或详情补全写入）
  final String uploader; // 上传者
  final String views; // 浏览量（字符串，兼容 "1.2k"）
  final String favorites; // 收藏量
  final String fileSize; // 文件大小 (如 "5.2 MB")
  final String createdAt; // 上传时间/创建时间
  final String mimeType; // 文件类型 (如 "image/png")

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

    // ✅ 默认值：保持旧代码不崩，同时允许“详情补全”覆盖
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

  UniWallpaper copyWith({
    String? id,
    String? sourceId,
    String? thumbUrl,
    String? fullUrl,
    double? width,
    double? height,
    String? grade,
    bool? isUgoira,
    bool? isAi,
    List<String>? tags,
    String? uploader,
    String? views,
    String? favorites,
    String? fileSize,
    String? createdAt,
    String? mimeType,
  }) {
    return UniWallpaper(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      fullUrl: fullUrl ?? this.fullUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      grade: grade ?? this.grade,
      isUgoira: isUgoira ?? this.isUgoira,
      isAi: isAi ?? this.isAi,
      tags: tags ?? this.tags,
      uploader: uploader ?? this.uploader,
      views: views ?? this.views,
      favorites: favorites ?? this.favorites,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}