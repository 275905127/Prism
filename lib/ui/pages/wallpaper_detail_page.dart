// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';

class WallpaperDetailPage extends StatefulWidget {
  final UniWallpaper wallpaper;

  /// ✅ 必须是“完整请求头”（含 Authorization / Client-ID / Referer 之类）
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
  
  // 图片缩放控制器
  final TransformationController _transformController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // Wallhaven 风格颜色
  static const Color _bgColor = Color(0xFF222222);
  static const Color _accentColor = Color(0xFFA6CC8B); // 类似 Wallhaven 的绿色
  static const Color _textColor = Color(0xFFEEEEEE);
  static const Color _subTextColor = Color(0xFFAAAAAA);

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
          if (mounted) _snack("❌ 需要相册权限才能保存");
          return;
        }
      }
    } catch (_) {}

    setState(() => _isDownloading = true);
    if (mounted) _snack("正在下载原图...");

    try {
      final Uint8List imageBytes = await context.read<WallpaperService>().downloadImageBytes(
            url: widget.wallpaper.fullUrl,
            headers: widget.headers,
          );

      final String extension = _detectExtension(imageBytes);
      final String fileName = "prism_${widget.wallpaper.sourceId}_${widget.wallpaper.id}.$extension";

      await Gal.putImageBytes(
        imageBytes,
        album: 'Prism',
        name: fileName,
      );

      if (mounted) _snack("✅ 图片已保存");
    } on GalException catch (e) {
      if (mounted) _snack("❌ 保存失败: ${e.type.message}");
    } catch (e) {
      if (mounted) _snack("❌ 下载错误: $e");
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _shareImage() {
    Share.share(widget.wallpaper.fullUrl);
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: widget.wallpaper.fullUrl));
    _snack("✅ 链接已复制");
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF333333),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = '${widget.wallpaper.sourceId}::${widget.wallpaper.id}';
    final w = widget.wallpaper;
    final hasSize = w.width > 0 && w.height > 0;
    
    // 构造一些显示用的数据
    final String resolution = hasSize ? "${w.width.toInt()} x ${w.height.toInt()}" : "Unknown Size";
    final String ratio = hasSize ? _calculateRatio(w.width, w.height) : "?";
    
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // 主滚动区域
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 图片区域
                GestureDetector(
                  onDoubleTap: _onDoubleTap,
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: 200,
                      maxHeight: MediaQuery.of(context).size.height * 0.85, // 图片最高占屏幕 85%
                    ),
                    width: double.infinity,
                    color: Colors.black,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Hero(
                        tag: heroTag,
                        child: CachedNetworkImage(
                          imageUrl: w.fullUrl,
                          httpHeaders: widget.headers,
                          fit: BoxFit.contain, // 保持比例完整显示
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(color: _accentColor),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. 操作栏 (模仿截图中的图标栏)
                Container(
                  color: const Color(0xFF2B2B2B), //稍微亮一点的背景
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionIcon(Icons.crop, "设为壁纸", () {
                         // 预留接口：设为壁纸
                         _snack("暂未实现壁纸设置"); 
                      }),
                      _buildActionIcon(Icons.content_copy, "复制链接", _copyUrl),
                      _buildActionIcon(Icons.share, "分享", _shareImage),
                      _buildActionIcon(Icons.download, "下载原图", _isDownloading ? null : _saveImage, isLoading: _isDownloading),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3. 详细信息区域
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 上传者/来源信息
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _accentColor,
                            child: Text(w.sourceId[0].toUpperCase(), 
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Source: ${w.sourceId}", 
                                style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                              Text("ID: ${w.id}", 
                                style: const TextStyle(color: _subTextColor, fontSize: 12)),
                            ],
                          ),
                          const Spacer(),
                          // 收藏按钮（视觉展示）
                          const Icon(Icons.bookmark_border, color: _accentColor, size: 28),
                        ],
                      ),
                      
                      const SizedBox(height: 20),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 20),

                      // 元数据列表
                      _buildMetaRow(Icons.link, w.fullUrl, isLink: true),
                      _buildMetaRow(Icons.aspect_ratio, resolution),
                      _buildMetaRow(Icons.crop_free, ratio),
                      if (w.isAi) _buildMetaRow(Icons.smart_toy, "AI Generated"),
                      if (w.isUgoira) _buildMetaRow(Icons.animation, "Animated (Ugoira)"),
                      _buildMetaRow(Icons.info_outline, w.grade?.toUpperCase() ?? "Safe"),

                      const SizedBox(height: 24),
                      
                      // 4. 标签区域
                      if (w.tags.isNotEmpty) ...[
                        const Text("Tags", style: TextStyle(color: _subTextColor, fontSize: 14)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: w.tags.map((tag) => _buildTag(tag)).toList(),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ],
                  ),
                ),
                
                // 底部留白，防止被系统手势条遮挡
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),

          // 顶部返回按钮 (悬浮)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const ContainerWithShadow(child: Icon(Icons.arrow_back, color: Colors.white)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 计算宽高比字符串
  String _calculateRatio(double w, double h) {
    if (w == 0 || h == 0) return "";
    final double r = w / h;
    if ((r - 1.77).abs() < 0.05) return "16:9";
    if ((r - 1.33).abs() < 0.05) return "4:3";
    if ((r - 1.6).abs() < 0.05) return "16:10";
    if ((r - 2.33).abs() < 0.1) return "21:9";
    if ((r - 0.56).abs() < 0.05) return "9:16";
    return r.toStringAsFixed(2);
  }

  // 构建单个操作图标
  Widget _buildActionIcon(IconData icon, String tooltip, VoidCallback? onTap, {bool isLoading = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: isLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor))
            : Icon(icon, color: _subTextColor, size: 26),
        ),
      ),
    );
  }

  // 构建元数据行
  Widget _buildMetaRow(IconData icon, String text, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _accentColor),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isLink ? _accentColor : _textColor,
                fontSize: 14,
                decoration: isLink ? TextDecoration.underline : null,
                decorationColor: _accentColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // 构建标签
  Widget _buildTag(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        border: Border.all(color: const Color(0xFF444444)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tag,
        style: const TextStyle(color: _accentColor, fontSize: 13),
      ),
    );
  }
}

// 简单的阴影容器，确保白色图标在浅色图上也能看清
class ContainerWithShadow extends StatelessWidget {
  final Widget child;
  const ContainerWithShadow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: Colors.black45, blurRadius: 8, spreadRadius: 0),
        ],
      ),
      child: child,
    );
  }
}
