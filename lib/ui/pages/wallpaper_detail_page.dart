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

  Future<void> _saveImage() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("开始下载..."), duration: Duration(milliseconds: 500)));
    
    try {
      final response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(
          responseType: ResponseType.bytes, 
          headers: widget.headers,
          // 增加超时，防止网络卡死
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      
      // 🔥 校验 1: 确保下载的是图片，而不是 403 Forbidden 的 HTML 页面
      final contentType = response.headers.value('content-type');
      if (contentType != null && !contentType.startsWith('image/')) {
         throw "服务器返回了非图片内容 ($contentType)，可能是防盗链拦截";
      }

      // 🔥 校验 2: 智能解析后缀名 (解决直链保存报错的核心！)
      String extension = "jpg"; // 默认后缀
      if (contentType != null) {
        if (contentType.contains("png")) extension = "png";
        else if (contentType.contains("gif")) extension = "gif";
        else if (contentType.contains("webp")) extension = "webp";
        else if (contentType.contains("jpeg")) extension = "jpg";
      }
      
      // 构造带后缀的文件名，Gal 就能识别了
      final String fileName = "prism_${DateTime.now().millisecondsSinceEpoch}.$extension";

      await Gal.putImageBytes(
        Uint8List.fromList(response.data), 
        album: 'Prism',
        name: fileName, // 🔥 显式传入文件名
      );

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 已保存到相册 (Prism)")));
    } on GalException catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 保存失败: ${e.type.message}")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 下载错误: $e")));
    } finally {
      if(mounted) setState(() => _isDownloading = false);
    }
  }

  void _shareImage() {
    Share.share(widget.wallpaper.fullUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. 图片层
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: SizedBox.expand(
              child: InteractiveViewer(
                child: Hero(
                  tag: widget.wallpaper.id,
                  child: CachedNetworkImage(
                    imageUrl: widget.wallpaper.fullUrl,
                    httpHeaders: widget.headers,
                    fit: BoxFit.contain,
                    progressIndicatorBuilder: (_,__,p) => Center(child: CircularProgressIndicator(value: p.progress, color: Colors.black)),
                    errorWidget: (context, url, error) => const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, size: 50, color: Colors.grey),
                          SizedBox(height: 10),
                          Text("图片加载失败", style: TextStyle(color: Colors.grey))
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. 顶部栏
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

          // 3. 底部栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24), 
              decoration: const BoxDecoration(
                color: Colors.white, 
                border: Border(
                  top: BorderSide(color: Colors.black12, width: 0.5), 
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: ${widget.wallpaper.id}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(
                    // 只有当宽高有效时才显示，否则显示 "Auto Size"
                    (widget.wallpaper.width > 0 && widget.wallpaper.height > 0)
                        ? "${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}"
                        : "Auto Size (Random Source)", 
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)
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
            Container(color: Colors.white54, child: const Center(child: CircularProgressIndicator(color: Colors.black))),
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
