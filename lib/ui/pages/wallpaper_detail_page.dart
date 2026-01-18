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

  Future<void> _saveImage() async {
    // ... 保存逻辑保持不变 ...
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      var response = await Dio().get(
        widget.wallpaper.fullUrl,
        options: Options(responseType: ResponseType.bytes, headers: widget.headers),
      );
      await Gal.putImageBytes(Uint8List.fromList(response.data), album: 'Prism');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 已保存")));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ 错误: $e")));
    } finally {
      if(mounted) setState(() => _isDownloading = false);
    }
  }

  void _shareImage() {
    Share.share(widget.wallpaper.fullUrl);
  }

  // 🔥 提取雾化渐变逻辑 (复用)
  BoxDecoration _buildFogDecoration({bool isBottom = false}) {
    final baseColor = Colors.white;
    final colors = [
      baseColor.withOpacity(0.94),
      baseColor.withOpacity(0.94),
      baseColor.withOpacity(0.90),
      baseColor.withOpacity(0.75),
      baseColor.withOpacity(0.50),
      baseColor.withOpacity(0.20),
      baseColor.withOpacity(0.0),
    ];
    
    // 如果是底部栏，渐变方向要反过来 (从下往上白)
    return BoxDecoration(
      gradient: LinearGradient(
        begin: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        end: isBottom ? Alignment.topCenter : Alignment.bottomCenter,
        colors: colors,
        stops: const [0.0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 图片层
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

          // 顶部栏 (雾化)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showInfo ? 0 : -100,
            left: 0, 
            right: 0,
            child: Container(
              height: 100, // 高度足够容纳渐变
              padding: const EdgeInsets.only(top: 40, left: 10),
              decoration: _buildFogDecoration(isBottom: false), // 🔥 应用顶部雾化
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // 底部栏 (雾化)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showInfo ? 0 : -180,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24), // Top padding 留给渐变过渡
              decoration: _buildFogDecoration(isBottom: true), // 🔥 应用底部雾化
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ID: ${widget.wallpaper.id}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: Colors.black),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
