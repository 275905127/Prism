// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../widgets/foggy_app_bar.dart';

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
  bool _showInfo = true;
  bool _isDownloading = false;
  
  // 用于控制图片的缩放重置
  final TransformationController _transformController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

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

  // 双击恢复/放大
  void _onDoubleTap() {
    Matrix4 matrix = _transformController.value;
    if (matrix.getMaxScaleOnAxis() > 1.0) {
      _animation = Matrix4Tween(begin: matrix, end: Matrix4.identity()).animate(_animationController);
      _animationController.forward(from: 0);
    } else {
      // 可选：双击放大
      // Matrix4 target = Matrix4.identity()..scale(2.0);
      // _animation = Matrix4Tween(begin: matrix, end: target).animate(_animationController);
      // _animationController.forward(from: 0);
    }
  }

  // 🔥 魔数识别后缀
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

    // 1. 权限检查 (适配 Android 10+ 免权限 和 iOS/Old Android 需权限)
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ 无法保存：需要相册权限")));
          }
          return;
        }
      }
    } catch (e) {
      // 忽略部分机型检查权限时的异常，尝试强行下载
      print('权限检查异常: $e');
    }

    setState(() => _isDownloading = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("开始下载..."), duration: Duration(milliseconds: 500)),
    );

    try {
      // 2. 统一走 Service 下载 (自动处理 Referer 等 Headers)
      final Uint8List imageBytes = await context.read<WallpaperService>().downloadImageBytes(
            url: widget.wallpaper.fullUrl,
            headers: widget.headers,
          );

      final String extension = _detectExtension(imageBytes);
      final String fileName = "prism_${widget.wallpaper.sourceId}_${widget.wallpaper.id}.$extension";

      // 3. 保存到相册
      await Gal.putImageBytes(
        imageBytes,
        album: 'Prism',
        name: fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 已保存到相册 (Prism)")));
      }
    } on GalException catch (e) {
      if (mounted) {
        String msg = "保存失败";
        if (e.type == GalExceptionType.accessDenied) msg = "没有相册权限";
        else if (e.type == GalExceptionType.notEnoughSpace) msg = "存储空间不足";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ $msg")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 下载错误: $e")));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _shareImage() {
    // 分享链接通常不需要 Headers，直接分享 URL 即可
    // 如果是私有链接，可能需要先下载再分享文件，这里暂只分享 URL
    Share.share(widget.wallpaper.fullUrl);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Hero tag 防冲突：同 id 不同源会炸/串
    final heroTag = '${widget.wallpaper.sourceId}::${widget.wallpaper.id}';

    // 构建标签列表 (适配 Pixiv 等源的特殊属性)
    final badges = <Widget>[];
    if (widget.wallpaper.isAi) {
      badges.add(_buildBadge('AI 生成', Colors.blue));
    }
    if (widget.wallpaper.isUgoira) {
      badges.add(_buildBadge('动图', Colors.purple));
    }
    if (widget.wallpaper.grade == 'nsfw') {
      badges.add(_buildBadge('R-18', Colors.red));
    } else if (widget.wallpaper.grade == 'sketchy') {
      badges.add(_buildBadge('R-15', Colors.orange));
    }

    return Scaffold(
      backgroundColor: Colors.black, // 看图通常用黑色背景
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            onDoubleTap: _onDoubleTap,
            child: SizedBox.expand(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 1.0,
                maxScale: 4.0,
                child: Hero(
                  tag: heroTag,
                  child: CachedNetworkImage(
                    imageUrl: widget.wallpaper.fullUrl,
                    httpHeaders: widget.headers, // ✅ 关键：透传 Headers (Referer)
                    fit: BoxFit.contain,
                    progressIndicatorBuilder: (_, __, p) =>
                        Center(child: CircularProgressIndicator(value: p.progress, color: Colors.white)),
                    errorWidget: (context, url, error) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, size: 50, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("图片加载失败", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // 顶部栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showInfo ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              padding: const EdgeInsets.only(top: 40, left: 10),
              // 使用渐变遮罩让文字更清晰
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // 底部信息栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -220, // 稍微加大隐藏距离以防万一
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "ID: ${widget.wallpaper.id}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Wrap(spacing: 6, children: badges),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.wallpaper.sourceId.toUpperCase(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (widget.wallpaper.width > 0 && widget.wallpaper.height > 0)
                            ? "${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}"
                            : "Auto Size",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBtn(Icons.download, "保存原图", _isDownloading ? null : _saveImage),
                      _buildBtn(Icons.share, "分享链接", _shareImage),
                    ],
                  ),
                  // 底部安全区适配
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
          
          // 下载中的遮罩
          if (_isDownloading)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text("正在下载...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBtn(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 140, // 固定宽度让按钮对齐更好看
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.black87, size: 26),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
