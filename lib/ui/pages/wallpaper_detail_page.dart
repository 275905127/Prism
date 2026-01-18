// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
// 🔥 已删除: import 'package:async_wallpaper/async_wallpaper.dart';
import '../../core/models/uni_wallpaper.dart';

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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // 1. 下载并保存到相册
  Future<void> _saveImage() async {
    if (_isDownloading) return;
    
    if (await Permission.storage.request().isDenied) {
      _showSnack("请授予存储权限");
      return;
    }

    setState(() => _isDownloading = true);
    _showSnack("开始下载...", isError: false);

    try {
      var response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: widget.headers,
        ),
      );
      
      final result = await ImageGallerySaver.saveImage(
        Uint8List.fromList(response.data),
        quality: 100,
        name: "prism_${widget.wallpaper.id}",
      );

      if (result['isSuccess']) {
        _showSnack("✅ 已保存到相册");
      } else {
        _showSnack("❌ 保存失败");
      }
    } catch (e) {
      _showSnack("❌ 下载出错: $e");
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  // 2. 系统分享
  void _shareImage() {
    Share.share('Check out this wallpaper: ${widget.wallpaper.fullUrl}');
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 图片区域
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: InteractiveViewer(
              child: Center(
                child: Hero(
                  tag: widget.wallpaper.id,
                  child: CachedNetworkImage(
                    imageUrl: widget.wallpaper.fullUrl,
                    httpHeaders: widget.headers,
                    fit: BoxFit.contain,
                    progressIndicatorBuilder: (context, url, progress) => Center(
                      child: CircularProgressIndicator(
                        value: progress.progress, 
                        color: Colors.white
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),

          // 顶部栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showInfo ? 0 : -80,
            left: 0,
            right: 0,
            child: Container(
              height: 90,
              padding: const EdgeInsets.only(top: 30, left: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black54, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // 底部控制栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -160,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: ${widget.wallpaper.id}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}", style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 20),
                  
                  // 🔥 修改后的按钮区域：只剩下载和分享
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFuncBtn(
                        Icons.download, 
                        "下载保存", 
                        _isDownloading ? null : _saveImage
                      ),
                      // 🔥 "设为壁纸" 按钮已移除
                      _buildFuncBtn(Icons.share, "分享图片", _shareImage),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (_isDownloading)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            )
        ],
      ),
    );
  }

  Widget _buildFuncBtn(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
