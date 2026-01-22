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
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // 缓存，避免 build 期间 provider lookup / 反复计算引发重建抖动
  Map<String, String>? _cachedHeaders;

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
        final a = _animation;
        if (a != null) {
          _transformController.value = a.value;
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ 只在依赖变化时重新解析 headers，避免每帧 build 都 read provider
    _cachedHeaders ??= _resolveImageHeaders();
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final matrix = _transformController.value;
    if (matrix.getMaxScaleOnAxis() > 1.0) {
      _animation = Matrix4Tween(begin: matrix, end: Matrix4.identity()).animate(_animationController);
      _animationController.forward(from: 0);
    } else {
      // 可选：双击放大到 2x（体验更像相册）
      final zoomed = Matrix4.identity()..scale(2.0);
      _animation = Matrix4Tween(begin: matrix, end: zoomed).animate(_animationController);
      _animationController.forward(from: 0);
    }
  }

  /// ✅ 统一计算图片 headers：
  /// 1) 优先用 widget.headers（兼容 SearchDelegate 传入）
  /// 2) 否则由 WallpaperService 基于 activeRule + wallpaper URL 决策（pximg referer/UA 等）
  Map<String, String>? _resolveImageHeaders() {
    final passed = widget.headers;
    if (passed != null && passed.isNotEmpty) return passed;

    final rule = context.read<SourceManager>().activeRule;
    return context.read<WallpaperService>().imageHeadersFor(
          wallpaper: widget.wallpaper,
          rule: rule,
        );
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
      final headers = _cachedHeaders ?? _resolveImageHeaders();

      final Uint8List imageBytes = await context.read<WallpaperService>().downloadImageBytes(
            url: widget.wallpaper.fullUrl,
            headers: headers,
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

  // 使用 query 参数传递搜索词
  void _searchUploader(String uploader) {
    showSearch(
      context: context,
      delegate: WallpaperSearchDelegate(),
      query: 'user:$uploader',
    );
  }

  void _searchSimilar() {
    showSearch(
      context: context,
      delegate: WallpaperSearchDelegate(),
      query: 'like:${widget.wallpaper.id}',
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  // ✅ 关键：固定图片展示区高度，避免 Sliver child 因图片 decode 改变高度导致“跳一下”
  double _imageViewportHeight(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // 你原本 maxHeight=0.85，这里直接固定为同等上限：稳定、可预期
    final h = screenH * 0.85;
    // 下限避免极小屏过小
    return h.clamp(320.0, 900.0);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallpaper;
    final heroTag = '${w.sourceId}::${w.id}';

    final resolvedHeaders = _cachedHeaders ?? _resolveImageHeaders();

    // 数据占位
    final String uploaderName = w.uploader.isNotEmpty ? w.uploader : "Unknown_User";
    final String viewsCount = w.views.isNotEmpty ? w.views : "-";
    final String favsCount = w.favorites.isNotEmpty ? w.favorites : "-";
    final String fileSize = w.fileSize.isNotEmpty ? w.fileSize : "-";
    final String uploadDate = w.createdAt.isNotEmpty ? w.createdAt : "-";
    final String fileType = w.mimeType.isNotEmpty ? w.mimeType : "image/jpeg";
    final String category = w.grade ?? "General";

    final hasSize = w.width > 0 && w.height > 0;
    final String resolution = hasSize ? "${w.width.toInt()} x ${w.height.toInt()}" : "Unknown";

    final double viewportH = _imageViewportHeight(context);

    return Scaffold(
      backgroundColor: _bgColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            floating: true,
            leading: IconButton(
              icon: const ContainerWithShadow(child: Icon(Icons.arrow_back, color: Colors.white)),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ✅ 图片区：固定高度 + 固定布局盒子 + 渐进式加载
          SliverToBoxAdapter(
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              child: SizedBox(
                height: viewportH,
                width: double.infinity,
                child: Container(
                  color: Colors.transparent,
                  child: Hero(
                    tag: heroTag,
                    // ✅ Hero 只包“固定尺寸的盒子”，避免 Hero 结束后又因图片尺寸变化二次跳动
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 1.0,
                        maxScale: 4.0,
                        // 可选：避免边缘溢出空白闪动
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox.expand(
                          // ✅ SizedBox.expand 锁定 child 的布局尺寸
                          child: _ProgressiveImage(
                            thumbUrl: w.thumbUrl,
                            fullUrl: w.fullUrl,
                            headers: resolvedHeaders,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 信息区
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        isProcessing: _isDownloading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 24),

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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "上传者: $uploaderName",
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const Text(
                                  "点击查看更多作品",
                                  style: TextStyle(color: _subTextColor, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
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
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

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

                  if (w.tags.isNotEmpty) ...[
                    const Row(
                      children: [
                        Icon(Icons.label, size: 18, color: _subTextColor),
                        SizedBox(width: 8),
                        Text(
                          "Tags",
                          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: w.tags.map((tag) => _buildTag(tag)).toList(),
                    ),
                  ],

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleAction(IconData icon, String label, VoidCallback? onTap, {bool isProcessing = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            isProcessing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor),
                  )
                : Icon(icon, color: _textColor, size: 26),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: _subTextColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }

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
                overflow: TextOverflow.ellipsis,
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

  Widget _buildTag(String tag) {
    return InkWell(
      onTap: () {
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

/// ✅ 渐进式图片：thumb 先出图，full 成功后淡入覆盖；
/// 关键是：外层 SizedBox.expand 锁住布局尺寸，内部用 FittedBox(contain) 适配，避免任何“加载前后布局变化”。
class _ProgressiveImage extends StatelessWidget {
  final String thumbUrl;
  final String fullUrl;
  final Map<String, String>? headers;

  const _ProgressiveImage({
    required this.thumbUrl,
    required this.fullUrl,
    required this.headers,
  });

  @override
  Widget build(BuildContext context) {
    Widget fitted(Widget child) {
      return Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: child,
        ),
      );
    }

    // 注意：FittedBox 需要 child 有“自身尺寸”，这里用 Image 组件提供 intrinsic；
    // 外层布局已被 SizedBox.expand 锁死，不会反向影响 Sliver 高度。
    final thumb = CachedNetworkImage(
      imageUrl: thumbUrl,
      httpHeaders: headers,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
      // 让其尽快解码
      placeholder: (_, __) => const SizedBox.shrink(),
    );

    final full = CachedNetworkImage(
      imageUrl: fullUrl,
      httpHeaders: headers,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景：避免透明导致的视觉“闪一下”
        Container(color: Colors.transparent),

        // thumb
        fitted(thumb),

        // full（淡入覆盖）
        fitted(full),

        // 中央 loading（只要 full 没出来，它也不会撑布局）
        const Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
          ),
        ),
      ],
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