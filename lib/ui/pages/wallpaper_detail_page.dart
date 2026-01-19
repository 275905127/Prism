// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/uni_wallpaper.dart';
import '../widgets/foggy_app_bar.dart';

class WallpaperDetailPage extends StatefulWidget {
  final UniWallpaper wallpaper;

  /// ✅ 必须是“完整请求头”（含 Authorization / Client-ID 之类）
  final Map<String, String>? headers;

  const WallpaperDetailPage({
    super.key,
    required this.wallpaper,
    this.headers,
  });

  @override
  State<WallpaperDetailPage> createState() => _WallpaperDetailPageState();
}

class _WallpaperDetailPageState extends State<WallpaperDetailPage> {
  bool _showInfo = true;
  bool _isDownloading = false;

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
    setState(() => _isDownloading = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("开始下载..."), duration: Duration(milliseconds: 500)),
    );

    try {
      final Map<String, String> finalHeaders = Map<String, String>.from(widget.headers ?? {});
      // 保底 UA
      finalHeaders.putIfAbsent(
        'User-Agent',
        () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: finalHeaders,
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final Uint8List imageBytes = Uint8List.fromList(response.data);

      if (imageBytes.lengthInBytes < 100) {
        throw "文件过小，可能是错误页面";
      }

      final String extension = _detectExtension(imageBytes);
      final String fileName = "prism_${DateTime.now().millisecondsSinceEpoch}.$extension";

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 保存失败: ${e.type.message}")));
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
    Share.share(widget.wallpaper.fullUrl);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Hero tag 防冲突：同 id 不同源会炸/串
    final heroTag = '${widget.wallpaper.sourceId}::${widget.wallpaper.id}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: SizedBox.expand(
              child: InteractiveViewer(
                child: Hero(
                  tag: heroTag,
                  child: CachedNetworkImage(
                    imageUrl: widget.wallpaper.fullUrl,
                    httpHeaders: widget.headers,
                    fit: BoxFit.contain,
                    progressIndicatorBuilder: (_, __, p) =>
                        Center(child: CircularProgressIndicator(value: p.progress, color: Colors.black)),
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
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showInfo ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              padding: const EdgeInsets.only(top: 40, left: 10),
              decoration: FoggyHelper.getDecoration(isBottom: false),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: ${widget.wallpaper.id}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(
                    (widget.wallpaper.width > 0 && widget.wallpaper.height > 0)
                        ? "${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}"
                        : "Auto Size (Random Source)",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBtn(Icons.download, "保存", _isDownloading ? null : _saveImage),
                      _buildBtn(Icons.share, "分享", _shareImage),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isDownloading)
            Container(
              color: Colors.white54,
              child: const Center(child: CircularProgressIndicator(color: Colors.black)),
            ),
        ],
      ),
    );
  }

  Widget _buildBtn(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.black, size: 26),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}