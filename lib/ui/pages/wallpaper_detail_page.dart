// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/models/uni_wallpaper.dart';
import '../widgets/foggy_app_bar.dart'; // 顶部依然可以用雾化，或者保留引用以防万一

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
      var response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(responseType: ResponseType.bytes, headers: widget.headers),
      );
      await Gal.putImageBytes(Uint8List.fromList(response.data), album: 'Prism');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 已保存到相册 (Prism)")));
    } on GalException catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 权限或保存错误: ${e.type.message}")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 网络错误: $e")));
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
                  ),
                ),
              ),
            ),
          ),

          // 2. 顶部栏 (保留雾化或改为纯白看你喜好，这里暂时保留雾化以维持顶部通透感)
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

          // 3. 底部栏 (🔥 已修改：纯白不透明 + 顶部细线)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              // 调整 Padding：不需要再为渐变留出超大的 top padding 了
              padding: const EdgeInsets.all(24), 
              decoration: const BoxDecoration(
                color: Colors.white, // 🔥 纯白背景，遮挡住下面的图片
                border: Border(
                  top: BorderSide(color: Colors.black12, width: 0.5), // 加一条极细的分割线，提升精致感
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: ${widget.wallpaper.id}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 4),
                  // 显示尺寸信息
                  Text(
                    "${widget.wallpaper.width.toInt()} x ${widget.wallpaper.height.toInt()}", 
                    style: TextStyle(color: Colors.grey[600], fontSize: 13)
                  ),
                  const SizedBox(height: 20),
                  
                  // 按钮区域
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
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12), //稍微加宽一点触控区
        decoration: BoxDecoration(
          color: Colors.grey[100], // 浅灰按钮底色
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
