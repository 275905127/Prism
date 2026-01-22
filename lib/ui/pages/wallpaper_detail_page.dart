// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/manager/source_manager.dart';
import '../../core/services/wallpaper_service.dart';
import 'wallpaper_search_delegate.dart';

class WallpaperDetailPage extends StatefulWidget {
  final UniWallpaper wallpaper;

  /// Compatibility: allow callers (e.g. SearchDelegate) to pass headers explicitly.
  final Map<String, String>? headers;
  const WallpaperDetailPage({
    super.key,
    required this.wallpaper,
    this.headers,
  });

  @override
  State<WallpaperDetailPage> createState() => _WallpaperDetailPageState();
}

class _WallpaperDetailPageState extends State<WallpaperDetailPage> with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  
  // 图片缩放控制
  final TransformationController _transformController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // Wallhaven Light Theme Colors (复刻白色风格)
  static const Color _bgColor = Colors.white;
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF777777);
  static const Color _accentColor = Color(0xFFA6CC8B); // Wallhaven Green
  static const Color _tagBgColor = Color(0xFFF0F0F0);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        _transformController.value = _animation!.value;
      });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    Matrix4 matrix = _transformController.value;
    if (matrix.getMaxScaleOnAxis() > 1.0) {
      _animation = Matrix4Tween(begin: matrix, end: Matrix4.identity()).animate(_animationController);
      _animationController.forward(from: 0);
    }
  }

  String _detectExtension(Uint8List bytes) {
    if (bytes.length < 12) return 'jpg';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
    if (bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) return 'webp';
    return 'jpg';
  }

  Future<void> _saveImage() async {
    if (_isDownloading) return;

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) _snack("❌ 需要相册权限");
          return;
        }
      }
    } catch (_) {}

    setState(() => _isDownloading = true);
    if (mounted) _snack("正在下载原图...");

    try {
      final Uint8List imageBytes = await context.read<WallpaperService>().downloadImageBytes(
            url: widget.wallpaper.fullUrl,
            headers: context.read<WallpaperService>().imageHeadersFor(
              wallpaper: widget.wallpaper,
              rule: context.read<SourceManager>().activeRule,
            ),
          );

      final String extension = _detectExtension(imageBytes);
      final String fileName = "prism_${widget.wallpaper.sourceId}_${widget.wallpaper.id}.$extension";

      await Gal.putImageBytes(
        imageBytes,
        album: 'Prism',
        name: fileName,
      );

      if (mounted) _snack("✅ 已保存到相册");
    } on GalException catch (e) {
      if (mounted) _snack("❌ 保存失败: ${e.type.message}");
    } catch (e) {
      if (mounted) _snack("❌ 下载错误: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _shareImage() => Share.share(widget.wallpaper.fullUrl);
  
  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: widget.wallpaper.fullUrl));
    _snack("✅ 链接已复制");
  }

  // 🔥 修复：使用 query 参数传递搜索词，而不是构造函数
  void _searchUploader(String uploader) {
    showSearch(
      context: context, 
      delegate: WallpaperSearchDelegate(), 
      query: 'user:$uploader',
    );
  }

  // 🔥 修复：使用 query 参数传递搜索词
  void _searchSimilar() {
    showSearch(
      context: context, 
      delegate: WallpaperSearchDelegate(), 
      query: 'like:${widget.wallpaper.id}',
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;
    final heroTag = '${w.sourceId}::${w.id}';

$insert
    
    // 📝 获取数据，如果为空显示占位符
    final String uploaderName = w.uploader.isNotEmpty ? w.uploader : "Unknown_User";
    final String viewsCount = w.views.isNotEmpty ? w.views : "-";
    final String favsCount = w.favorites.isNotEmpty ? w.favorites : "-";
    final String fileSize = w.fileSize.isNotEmpty ? w.fileSize : "-";
    final String uploadDate = w.createdAt.isNotEmpty ? w.createdAt : "-";
    final String fileType = w.mimeType.isNotEmpty ? w.mimeType : "image/jpeg";
    final String category = w.grade ?? "General";

    final hasSize = w.width > 0 && w.height > 0;
    final String resolution = hasSize ? "${w.width.toInt()} x ${w.height.toInt()}" : "Unknown";

    return Scaffold(
      backgroundColor: _bgColor,
      // 使用 CustomScrollView 实现图片随滚动推上去的效果
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. 顶部栏 (透明/悬浮)
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            floating: true,
            leading: IconButton(
              icon: const ContainerWithShadow(child: Icon(Icons.arrow_back, color: Colors.white)),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 2. 图片展示区 (SliverToBoxAdapter)
          SliverToBoxAdapter(
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: Container(
                // 图片底色保持黑，以免透明图或加载时太亮眼
                // 改为透明，透出页面的白色背景
                color: Colors.transparent,

                constraints: BoxConstraints(
                  minHeight: 300,
                  // 限制最大高度，防止超长图占满屏幕无法下滑
                  maxHeight: MediaQuery.of(context).size.height * 0.85, 
                ),
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Hero(
                    tag: heroTag,
                    child: CachedNetworkImage(
                      imageUrl: w.fullUrl,
                      httpHeaders: resolvedHeaders,
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. 信息详情区 (白底)
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 操作栏 (复制/分享/下载) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSimpleAction(Icons.crop_free, "设为壁纸", () => _snack("暂未实现")),
                      _buildSimpleAction(Icons.copy, "复制链接", _copyUrl),
                      _buildSimpleAction(Icons.share, "分享", _shareImage),
                      _buildSimpleAction(
                        Icons.download, 
                        "下载原图", 
                        _isDownloading ? null : _saveImage, 
                        isProcessing: _isDownloading
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 24),

                  // --- 上传者信息 ---
                  InkWell(
                    onTap: () => _searchUploader(uploaderName),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: _accentColor,
                            child: Text(
                              uploaderName.isNotEmpty ? uploaderName[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("上传者: $uploaderName",
                                    style: const TextStyle(
                                        color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                const Text("点击查看更多作品", 
                                    style: TextStyle(color: _subTextColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          // 关注按钮样式
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border.all(color: _accentColor),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.add, size: 16, color: _accentColor),
                                SizedBox(width: 4),
                                Text("关注", style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- 详细参数 Grid ---
                  // 复刻 Wallhaven 侧边栏信息布局
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.visibility, "$viewsCount 浏览", Icons.favorite, "$favsCount 收藏"),
                        const SizedBox(height: 12),
                        _buildInfoRow(Icons.aspect_ratio, resolution, Icons.sd_storage, fileSize),
                        const SizedBox(height: 12),
                        _buildInfoRow(Icons.calendar_today, uploadDate, Icons.category, category),
                        const SizedBox(height: 12),
                        _buildInfoRow(Icons.image, fileType, Icons.link, "查看源地址", isLink: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- 相似搜索按钮 ---
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.image_search, color: _textColor),
                      label: const Text("查找相似图片 (Similar)", style: TextStyle(color: _textColor)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFDDDDDD)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _searchSimilar,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- 标签区域 ---
                  if (w.tags.isNotEmpty) ...[
                    const Row(
                      children: [
                        Icon(Icons.label, size: 18, color: _subTextColor),
                        SizedBox(width: 8),
                        Text("Tags", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: w.tags.map((tag) => _buildTag(tag)).toList(),
                    ),
                  ],

                  // 底部留白
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建简单的图标+文字按钮 (无背景)
  Widget _buildSimpleAction(IconData icon, String label, VoidCallback? onTap, {bool isProcessing = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            isProcessing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor))
                : Icon(icon, color: _textColor, size: 26),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: _subTextColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // 构建一行两个信息
  Widget _buildInfoRow(IconData i1, String t1, IconData i2, String t2, {bool isLink = false}) {
    Widget item(IconData i, String t, bool link) {
      return Expanded(
        child: Row(
          children: [
            Icon(i, size: 16, color: _accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t, 
                style: TextStyle(
                  color: link ? _accentColor : _textColor, 
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  decoration: link ? TextDecoration.underline : null,
                  decorationColor: _accentColor,
                ),
                maxLines: 1, 
                overflow: TextOverflow.ellipsis
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        item(i1, t1, false),
        const SizedBox(width: 16),
        item(i2, t2, isLink),
      ],
    );
  }

  // 构建胶囊标签
  Widget _buildTag(String tag) {
    return InkWell(
      onTap: () {
        // 🔥 修复：使用 query 参数传递搜索词
        showSearch(
          context: context, 
          delegate: WallpaperSearchDelegate(), 
          query: tag,
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _tagBgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Text(
          tag,
          style: const TextStyle(color: _textColor, fontSize: 13),
        ),
      ),
    );
  }
}

// 阴影容器，用于返回按钮
class ContainerWithShadow extends StatelessWidget {
  final Widget child;
  const ContainerWithShadow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: child,
    );
  }
}