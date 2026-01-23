// lib/ui/pages/wallpaper_detail_page.dart
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/uni_wallpaper.dart';
import '../../core/manager/source_manager.dart';
import '../../core/services/wallpaper_service.dart';
import 'wallpaper_search_delegate.dart';

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

class _WallpaperDetailPageState extends State<WallpaperDetailPage>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;

  // ===== 详情（两阶段） =====
  late UniWallpaper _wallpaper;
  bool _detailHydrating = false;
  bool _detailHydrated = false;

  // ===== 相似列表 =====
  bool _similarExpanded = false;
  bool _similarLoading = false;
  bool _similarHasMore = true;
  int _similarPage = 1;
  final List<UniWallpaper> _similarList = [];

  // ===== 图片缩放 =====
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  Map<String, String>? _cachedHeaders;

  static const Color _bgColor = Colors.white;
  static const Color _textColor = Color(0xFF333333);
  static const Color _subTextColor = Color(0xFF777777);
  static const Color _accentColor = Color(0xFFA6CC8B);
  static const Color _tagBgColor = Color(0xFFF0F0F0);

  @override
  void initState() {
    super.initState();
    _wallpaper = widget.wallpaper;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final a = _animation;
        if (a != null) _transformController.value = a.value;
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedHeaders ??= _resolveImageHeaders();

    if (!_detailHydrated && !_detailHydrating) {
      _detailHydrating = true;
      _hydrateDetailIfPossible();
    }
  }

  Future<void> _hydrateDetailIfPossible() async {
    try {
      final rule = context.read<SourceManager>().activeRule;
      if (rule == null) {
        setState(() => _detailHydrated = true);
        return;
      }

      final updated = await context.read<WallpaperService>().fetchDetail(
            base: _wallpaper,
            rule: rule,
          );

      if (!mounted) return;
      setState(() {
        _wallpaper = updated;
        _detailHydrated = true;
      });
    } catch (_) {
      if (mounted) setState(() => _detailHydrated = true);
    } finally {
      _detailHydrating = false;
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ================= 相似加载 =================

  void _toggleSimilar() {
    setState(() => _similarExpanded = !_similarExpanded);
    if (_similarExpanded && _similarList.isEmpty) {
      _loadSimilar();
    }
  }

  Future<void> _loadSimilar() async {
    if (_similarLoading || !_similarHasMore) return;

    final rule = context.read<SourceManager>().activeRule;
    if (rule == null) return;

    setState(() => _similarLoading = true);

    try {
      final list = await context.read<WallpaperService>().fetchSimilar(
            seed: _wallpaper,
            rule: rule,
            page: _similarPage,
          );

      if (!mounted) return;
      setState(() {
        if (list.isEmpty) {
          _similarHasMore = false;
        } else {
          _similarList.addAll(
            list.where((e) => e.id != _wallpaper.id),
          );
          _similarPage++;
        }
      });
    } catch (_) {
      if (mounted) _snack("加载相似作品失败");
    } finally {
      if (mounted) setState(() => _similarLoading = false);
    }
  }

  // ================= 辅助 =================

  Map<String, String>? _resolveImageHeaders() {
    if (widget.headers != null && widget.headers!.isNotEmpty)
      return widget.headers;
    final rule = context.read<SourceManager>().activeRule;
    return context.read<WallpaperService>().imageHeadersFor(
          wallpaper: _wallpaper,
          rule: rule,
        );
  }

  void _onDoubleTap() {
    final m = _transformController.value;
    final end = m.getMaxScaleOnAxis() > 1
        ? Matrix4.identity()
        : (Matrix4.identity()..scale(2.0));
    _animation = Matrix4Tween(begin: m, end: end).animate(_animationController);
    _animationController.forward(from: 0);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  // ================= Build Components =================

  // 构建元数据区域 (作者、标签、统计)
  Widget _buildMetaInfo(UniWallpaper w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 作者与时间行
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[200],
                radius: 18,
                child: Text(
                  w.uploader.isNotEmpty ? w.uploader[0].toUpperCase() : 'U',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.uploader,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (w.createdAt.isNotEmpty)
                      Text(
                        w.createdAt,
                        style:
                            const TextStyle(fontSize: 12, color: _subTextColor),
                      ),
                  ],
                ),
              ),
              // AI 标识
              if (w.isAi)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                  ),
                  child: const Text('AI 生成',
                      style: TextStyle(fontSize: 10, color: Colors.blueAccent)),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // 2. 数据统计行 (浏览、收藏、尺寸)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(Icons.remove_red_eye_outlined,
                  w.views.isEmpty ? '-' : w.views, '浏览'),
              _buildStatItem(Icons.favorite_border,
                  w.favorites.isEmpty ? '-' : w.favorites, '收藏'),
              _buildStatItem(Icons.aspect_ratio,
                  '${w.width.toInt()}x${w.height.toInt()}', '分辨率'),
              _buildStatItem(
                  Icons.data_usage, w.fileSize.isEmpty ? '-' : w.fileSize, '大小'),
            ],
          ),

          const SizedBox(height: 16),

          // 3. 标签流
          if (w.tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: w.tags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _tagBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(fontSize: 12, color: _textColor),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // 辅助小组件：单个统计项
  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _subTextColor),
            const SizedBox(width: 4),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _subTextColor)),
      ],
    );
  }

  // ================= Main Build =================

  @override
  Widget build(BuildContext context) {
    final w = _wallpaper;
    final headers = _cachedHeaders;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _bgColor,
      // 使用 Stack 实现顶部悬浮栏覆盖
      body: Stack(
        children: [
          // 底层内容滚动视图
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 图片区域
              SliverToBoxAdapter(
                child: GestureDetector(
                  onDoubleTap: _onDoubleTap,
                  child: Hero(
                    tag: '${w.sourceId}::${w.id}',
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 1,
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: w.fullUrl,
                        httpHeaders: headers,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              // 元数据展示区域 (新增)
              SliverToBoxAdapter(
                child: _buildMetaInfo(w),
              ),

              // 分割间距
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // 相似入口按钮
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    icon: Icon(
                      _similarExpanded ? Icons.expand_less : Icons.auto_awesome,
                      color: _textColor,
                    ),
                    label: Text(
                      _similarExpanded ? "收起相似作品" : "查看更多相似作品",
                      style: const TextStyle(color: _textColor),
                    ),
                    onPressed: _toggleSimilar,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFEEEEEE)),
                    ),
                  ),
                ),
              ),

              // 相似列表
              if (_similarExpanded)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: MasonryGridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      itemCount: _similarList.length,
                      itemBuilder: (context, index) {
                        final item = _similarList[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    WallpaperDetailPage(wallpaper: item),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: item.thumbUrl,
                              httpHeaders: headers,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              if (_similarExpanded)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: _similarLoading
                          ? const CircularProgressIndicator()
                          : (_similarHasMore
                              ? TextButton(
                                  onPressed: _loadSimilar,
                                  child: const Text("加载更多"),
                                )
                              : const Text(
                                  "没有更多了",
                                  style: TextStyle(color: _subTextColor),
                                )),
                    ),
                  ),
                ),

              SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 32),
              ),
            ],
          ),

          // 顶层悬浮：渐变雾化 AppBar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kToolbarHeight + topPadding,
            child: Container(
              padding: EdgeInsets.only(top: topPadding),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.9),
                    Colors.white.withOpacity(0.7),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              child: Row(
                children: [
                  const BackButton(color: Colors.black),
                  const Expanded(child: SizedBox()),
                  // 如果需要右上角按钮（如下载/分享），可以在这里添加
                  // IconButton(icon: Icon(Icons.share), onPressed: () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
