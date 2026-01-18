// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart'; // 🔥 引入新库
import 'package:share_plus/share_plus.dart';
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

  // 🔥 1. 新的保存逻辑 (使用 Gal)
  Future<void> _saveImage() async {
    if (_isDownloading) return;
    
    // Gal 会自动处理权限，如果在 Android 10+ 甚至不需要权限
    // 我们只需要捕获可能的“用户拒绝”异常即可

    setState(() => _isDownloading = true);
    _showSnack("开始下载...", isError: false);

    try {
      // 1. 下载图片数据
      var response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: widget.headers,
        ),
      );
      
      // 2. 保存到相册 (Gal 及其简单)
      // album 参数可以指定相册名字，比如 "Prism"
      await Gal.putImageBytes(
        Uint8List.fromList(response.data),
        album: 'Prism', 
      );

      _showSnack("✅ 已保存到相册 (Prism)");
    } on GalException catch (e) {
      // 处理特定的 Gal 错误 (比如没有权限)
      _showSnack("❌ 保存失败: ${e.type.message}");
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
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFuncBtn(
                        Icons.download, 
                        "下载保存", 
                        _isDownloading ? null : _saveImage
                      ),
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
