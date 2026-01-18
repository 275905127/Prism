// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
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
    // 进入详情页时，状态栏字体变黑
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    // 隐藏状态栏实现沉浸式，或者保留状态栏看你需要
    // 这里我们保留状态栏，但背景透明
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    // 退出时恢复
    super.dispose();
  }

  Future<void> _saveImage() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    _showSnack("开始下载...", isError: false);

    try {
      var response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(responseType: ResponseType.bytes, headers: widget.headers),
      );
      await Gal.putImageBytes(Uint8List.fromList(response.data), album: 'Prism');
      _showSnack("✅ 已保存到相册");
    } on GalException catch (e) {
      _showSnack("❌ 保存失败: ${e.type.message}");
    } catch (e) {
      _showSnack("❌ 下载出错: $e");
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _shareImage() {
    Share.share('Check out this wallpaper: ${widget.wallpaper.fullUrl}');
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)), // SnackBar 保持黑底白字，对比度高
        backgroundColor: isError ? Colors.redAccent : Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 🔥 背景改为纯白
      body: Stack(
        children: [
          // 1. 图片层
          GestureDetector(
            onTap: () => setState(() => _showInfo = !_showInfo),
            child: Container(
              color: Colors.white, // 图片背景白
              width: double.infinity,
              height: double.infinity,
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
                          color: Colors.black // 加载圈变黑
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. 顶部栏 (纯白面板)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showInfo ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: 100, // 稍微高一点，避开刘海
              padding: const EdgeInsets.only(top: 40, left: 10),
              color: Colors.white.withOpacity(0.95), // 🔥 纯白背景，微透
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black), // 🔥 黑色图标
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),

          // 3. 底部栏 (纯白面板)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95), // 🔥 纯白背景
                border: const Border(top: BorderSide(color: Colors.black12)), // 顶部细线分割
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ID: ${widget.wallpaper.id}", 
                    style: const TextStyle(
                      color: Colors.black, // 🔥 黑色文字
                      fontWeight: FontWeight.bold,
                      fontSize: 18
                    )
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}", 
                    style: TextStyle(color: Colors.grey[600], fontSize: 14) // 灰色副标题
                  ),
                  const SizedBox(height: 24),
                  
                  // 功能按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildFuncBtn(Icons.download, "保存", _isDownloading ? null : _saveImage),
                      _buildFuncBtn(Icons.share, "分享", _shareImage),
                    ],
                  ),
                  const SizedBox(height: 10), // 底部安全区
                ],
              ),
            ),
          ),
          
          if (_isDownloading)
            Container(
              color: Colors.white70, // 遮罩也改亮色
              child: const Center(child: CircularProgressIndicator(color: Colors.black)),
            )
        ],
      ),
    );
  }

  Widget _buildFuncBtn(IconData icon, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[100], // 浅灰底色的按钮
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black, size: 26), // 🔥 黑色图标
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.black87, fontSize: 12)), // 🔥 黑色文字
          ],
        ),
      ),
    );
  }
}
