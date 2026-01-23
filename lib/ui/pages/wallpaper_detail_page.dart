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
import '../widgets/foggy_app_bar.dart'; // 确保引用了 FoggyHelper
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

  // ✅ 详情补全后的 wallpaper（两阶段模型 Stage 2）
  late UniWallpaper _wallpaper;

  bool _detailHydrating = false;
  bool _detailHydrated = false;

  // ✅ 相似推荐（内嵌列表）
  bool _similarLoading = false;
  bool _similarLoaded = false;
  List<UniWallpaper> _similar = const [];

  // 图片缩放控制
  final TransformationController _transformController = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // 缓存，避免 build 期间 provider lookup / 反复计算引发重建抖动
  Map<String, String>? _cachedHeaders;

  // Colors
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
        if (a != null) {
          _transformController.value = a.value;
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedHeaders ??= _resolveImageHeaders();

    // ✅ 只触发一次详情补全（Stage 2）
    if (!_detailHydrated && !_detailHydrating) {
      _detailHydrating = true;
      _hydrateDetailIfPossible();
    }

    // ✅ 只触发一次相似推荐加载（不依赖详情补全完成）
    if (!_similarLoaded && !_similarLoading) {
      _similarLoading = true;
      _loadSimilarInline();
    }
  }

  Future<void> _hydrateDetailIfPossible() async {
    try {
      final rule = context.read<SourceManager>().activeRule;
      if (rule == null) {
        if (!mounted) return;
        setState(() => _detailHydrated = true);
        return;
      }

      // ✅ 新版 WallpaperService：fetchDetail({base, rule}) —— Stage 2 真正补全发生在 Service/Engine
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
      // 详情补全失败不影响页面展示（保持“列表数据”）
      if (!mounted) return;
      setState(() => _detailHydrated = true);
    } finally {
      _detailHydrating = false;
    }
  }

  Future<void> _loadSimilarInline() async {
    try {
      final rule = context.read<SourceManager>().activeRule;
      if (rule == null) {
        if (!mounted) return;
        setState(() {
          _similar = const [];
          _similarLoaded = true;
        });
        return;
      }

      final service = context.read<WallpaperService>();

      // ✅ 相似推荐：优先走 fetchSimilar（Pixiv 可专用；其他走 query fallback）
      final list = await service.fetchSimilar(
        seed: _wallpaper,
        rule: rule,
        page: 1,
      );

      if (!mounted) return;
      setState(() {
        // 去重：避免把自己塞回来
        _similar = list.where((e) => e.id != _wallpaper.id).take(18).toList(growable: false);
        _similarLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _similar = const [];
        _similarLoaded = true;
      });
    } finally {
      _similarLoading = false;
    }
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
      final zoomed = Matrix4.identity()..scale(2.0);
      _animation = Matrix4Tween(begin: matrix, end: zoomed).animate(_animationController);
      _animationController.forward(from: 0);
    }
  }

  Map<String, String>? _resolveImageHeaders() {
    final passed = widget.headers;
    if (passed != null && passed.isNotEmpty) return passed;

    final rule = context.read<SourceManager>().activeRule;
    return context.read<WallpaperService>().imageHeadersFor(
          wallpaper: _wallpaper,
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
            url: _wallpaper.fullUrl,
            headers: headers,
          );

      final String extension = _detectExtension(imageBytes);
      final String fileName = "prism_${_wallpaper.sourceId}_${_wallpaper.id}.$extension";

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

  void _shareImage() => Share.share(_wallpaper.fullUrl);

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _wallpaper.fullUrl));
    _snack("✅ 链接已复制");
  }

  void _searchUploader(String uploader) {
    final u = uploader.trim();
    if (u.isEmpty || u.toLowerCase() == 'unknown user') {
      _snack("没有可用的上传者信息");
      return;
    }

    showSearch(
      context: context,
      delegate: WallpaperSearchDelegate(),
      query: 'user:$u',
    );
  }

  void _searchSimilar() {
   final service = context.read<WallpaperService>();
   final rule = context.read<SourceManager>().activeRule;

   if (rule == null) {
     _snack("当前没有可用的图源规则");
     return;
  }

   final query = service
      .buildSimilarQuery(
        _wallpaper,
        rule: rule,
      )
      .trim();

   if (query.isEmpty) {
    _snack("未能生成相似搜索条件");
    return;
  }

   showSearch(
    context: context,
    delegate: WallpaperSearchDelegate(),
    query: query,
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

  double _imageViewportHeight(BuildContext context, UniWallpaper w) {
    final screenW = MediaQuery.of(context).size.width;

    if (w.width > 0 && w.height > 0) {
      final ratio = w.width / w.height;
      final h = screenW / ratio;
      return h.clamp(220.0, 5000.0);
    }

    final screenH = MediaQuery.of(context).size.height;
    final h = screenH * 0.85;
    return h.clamp(320.0, 900.0);
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallpaper;
    final heroTag = '${w.sourceId}::${w.id}';

    final resolvedHeaders = _cachedHeaders ?? _resolveImageHeaders();

    // ✅ 详情信息项：从两阶段补全后的 _wallpaper 读取
    final String uploaderName = w.uploader.isNotEmpty ? w.uploader : "Unknown User";
    final String viewsCount = w.views.isNotEmpty ? w.views : "-";
    final String favsCount = w.favorites.isNotEmpty ? w.favorites : "-";
    final String fileSize = w.fileSize.isNotEmpty ? w.fileSize : "-";
    final String uploadDate = w.createdAt.isNotEmpty ? w.createdAt : "-";
    final String fileType = w.mimeType.isNotEmpty ? w.mimeType : "image/jpeg";
    final String category = (w.grade != null && w.grade!.trim().isNotEmpty) ? w.grade!.trim() : "General";

    final hasSize = w.width > 0 && w.height > 0;
    final String resolution = hasSize ? "${w.width.toInt()} x ${w.height.toInt()}" : "Unknown";

    final double viewportH = _imageViewportHeight(context, w);
    
    // 使用 FoggyHelper 构造渐变
    final gradientDeco = FoggyHelper.getDecoration(isBottom: false); 

    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
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
                        child: ClipRect(
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            minScale: 1.0,
                            maxScale: 4.0,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.expand(
                              child: _FullImageOnly(
                                url: w.fullUrl,
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
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 操作栏
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

                      const SizedBox(height: 12),

                      // ✅ 详情补全状态（轻提示）
                      if (!_detailHydrated)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '正在补全详情信息…',
                            style: TextStyle(color: _subTextColor, fontSize: 12),
                          ),
                        ),

                      const SizedBox(height: 24),
                      const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 24),

                      // 上传者
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
                                      "查看该作者的更多作品",
                                      style: TextStyle(color: _subTextColor, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ✅ 详细参数展示
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
                            _buildInfoRow(
                              Icons.image,
                              fileType,
                              Icons.link,
                              "查看源地址",
                              isLink: true,
                              onTapLink: () {
                                Clipboard.setData(ClipboardData(text: w.fullUrl));
                                _snack("✅ 源地址已复制");
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 相似搜索（跳搜索页）
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome, color: _textColor),
                          label: const Text(
                            "查看更多相似作品",
                            style: TextStyle(color: _textColor),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFDDDDDD)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _searchSimilar,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ✅ 内嵌相似推荐列表
                      _buildInlineSimilarSection(),

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

          // ✅ 顶部雾化渐变栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top + kToolbarHeight,
              decoration: gradientDeco,
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const _BackButtonBadge(),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineSimilarSection() {
    // 未加载完成时，给轻量提示
    if (!_similarLoaded) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          '正在加载相似推荐…',
          style: TextStyle(color: _subTextColor, fontSize: 12),
        ),
      );
    }

    if (_similar.isEmpty) {
      return Row(
        children: [
          const Expanded(
            child: Text(
              '暂无相似推荐',
              style: TextStyle(color: _subTextColor, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              if (_similarLoading) return;
              setState(() {
                _similarLoaded = false;
                _similarLoading = true;
              });
              _loadSimilarInline();
            },
            child: const Text('重试'),
          ),
        ],
      );
    }

    final rule = context.read<SourceManager>().activeRule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: _subTextColor),
            SizedBox(width: 8),
            Text(
              "相似推荐",
              style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _similar.length.clamp(0, 18),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final it = _similar[index];
              final headers = context.read<WallpaperService>().imageHeadersFor(wallpaper: it, rule: rule);

              final tag = '${it.sourceId}::${it.id}';
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WallpaperDetailPage(
                        wallpaper: it,
                        headers: headers,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 148,
                    color: const Color(0xFFF3F3F3),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Hero(
                            tag: tag,
                            child: CachedNetworkImage(
                              imageUrl: it.thumbUrl.isNotEmpty ? it.thumbUrl : it.fullUrl,
                              httpHeaders: headers,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              it.uploader.isNotEmpty ? it.uploader : it.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

  Widget _buildInfoRow(
    IconData i1,
    String t1,
    IconData i2,
    String t2, {
    bool isLink = false,
    VoidCallback? onTapLink,
  }) {
    Widget item(IconData i, String t, bool link, {VoidCallback? onTap}) {
      final text = Text(
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
      );

      return Expanded(
        child: Row(
          children: [
            Icon(i, size: 16, color: _accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: link
                  ? InkWell(
                      onTap: onTap,
                      child: text,
                    )
                  : text,
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        item(i1, t1, false),
        const SizedBox(width: 16),
        item(i2, t2, isLink, onTap: onTapLink),
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

class _BackButtonBadge extends StatelessWidget {
  const _BackButtonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 4),
            color: Color(0x1A000000),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: const Icon(Icons.arrow_back, color: Colors.black),
    );
  }
}

class _FullImageOnly extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;

  const _FullImageOnly({
    required this.url,
    required this.headers,
  });

  @override
  State<_FullImageOnly> createState() => _FullImageOnlyState();
}

class _FullImageOnlyState extends State<_FullImageOnly> {
  bool _loaded = false;
  bool _failed = false;

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

    return Stack(
      children: [
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            httpHeaders: widget.headers,
            fit: BoxFit.contain,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholderFadeInDuration: const Duration(milliseconds: 60),
            imageBuilder: (context, provider) {
              if (!_loaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _loaded = true);
                });
              }
              return fitted(Image(image: provider));
            },
            placeholder: (context, url) => const SizedBox.shrink(),
            errorWidget: (context, url, error) {
              if (!_failed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _failed = true);
                });
              }
              return const Center(child: Icon(Icons.broken_image_outlined, size: 46, color: Colors.grey));
            },
          ),
        ),
        if (!_loaded && !_failed)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
