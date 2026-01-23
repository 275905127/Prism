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
  final TransformationController _transformController = TransformationController();
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
    if (widget.headers != null && widget.headers!.isNotEmpty) return widget.headers;
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
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1400)),
    );
  }

  // ================= Build =================

  @override
  Widget build(BuildContext context) {
    final w = _wallpaper;
    final headers = _cachedHeaders;

    return Scaffold(
      backgroundColor: _bgColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
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

          // ===== 相似入口按钮 =====
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
              ),
            ),
          ),

          // ===== 相似列表 =====
          if (_similarExpanded)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            builder: (_) => WallpaperDetailPage(wallpaper: item),
                          ),
                        );
                      },
                      child: CachedNetworkImage(
                        imageUrl: item.thumbUrl,
                        httpHeaders: headers,
                        fit: BoxFit.cover,
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
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
          ),
        ],
      ),
    );
  }
}