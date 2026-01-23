// lib/ui/pages/wallpaper_search_delegate.dart
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/source_rule.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart'; // 引入 Service
import 'wallpaper_detail_page.dart';

class WallpaperSearchDelegate extends SearchDelegate {
  /// ✅ 可选：锁死图源，避免“like:ID / user:xxx / tag”串到别的源
  final SourceRule? initialRule;

  WallpaperSearchDelegate({this.initialRule});

  // ... (appBarTheme, buildActions, buildLeading 保持不变)
  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.grey),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, color: Colors.black),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.black),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // ✅ 关键改动：允许空 query 展示默认列表（query 为空时传 null 给 service.fetch）
    return _SearchResults(
      query: query,
      initialRule: initialRule,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(color: Colors.white);
  }
}

class _SearchResults extends StatefulWidget {
  final String query;
  final SourceRule? initialRule;

  const _SearchResults({
    required this.query,
    required this.initialRule,
  });

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  final ScrollController _scrollController = ScrollController();
  List<UniWallpaper> _wallpapers = [];
  bool _loading = false;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _doSearch(refresh: true);
  }

  @override
  void didUpdateWidget(covariant _SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ 搜索词变化：刷新
    if (oldWidget.query.trim() != widget.query.trim()) {
      _doSearch(refresh: true);
    }
    // ✅ 锁死 rule 变化：也刷新
    if (oldWidget.initialRule?.id != widget.initialRule?.id) {
      _doSearch(refresh: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || !_hasMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _doSearch(refresh: false);
    }
  }

  SourceRule? _resolveRule() {
    // ✅ 优先使用锁死的 initialRule；否则用当前 activeRule
    final manager = context.read<SourceManager>();
    return widget.initialRule ?? manager.activeRule;
  }

  Future<void> _doSearch({required bool refresh}) async {
    if (_loading) return;

    final rule = _resolveRule();
    if (rule == null) return;

    setState(() {
      _loading = true;
      if (refresh) {
        _page = 1;
        _hasMore = true;
      }
    });

    try {
      final q = widget.query.trim();

      // ✅ 关键改动：空搜索词 => query 传 null，让后端走默认列表（而不是直接清空）
      final String? actualQuery = q.isEmpty ? null : q;

      final List<UniWallpaper> data = await context.read<WallpaperService>().fetch(
            rule,
            page: _page,
            query: actualQuery,
          );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _wallpapers = data;
        } else {
          _wallpapers.addAll(data);
        }

        if (data.isEmpty) {
          _hasMore = false;
        } else {
          _page++;
        }

        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = context.watch<SourceManager>().activeRule;
    final lockedRule = widget.initialRule;

    // 这里展示用哪个规则：以实际请求规则为准
    final usingRule = lockedRule ?? rule;

    return Stack(
      children: [
        MasonryGridView.count(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          itemCount: _wallpapers.length,
          itemBuilder: (context, index) {
            final paper = _wallpapers[index];

            // ✅ 关键改动：每张图的 headers 走 imageHeadersFor（避免 Referer/Cookie 不一致）
            final headers = context.read<WallpaperService>().imageHeadersFor(
                  wallpaper: paper,
                  rule: usingRule,
                );

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WallpaperDetailPage(
                    wallpaper: paper,
                    headers: headers,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: paper.thumbUrl.isNotEmpty ? paper.thumbUrl : paper.fullUrl,
                  httpHeaders: headers,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(color: Colors.grey[100], height: 160),
                  errorWidget: (c, u, e) => Container(
                    color: Colors.grey[50],
                    height: 160,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            );
          },
        ),
        if (_loading && _page == 1)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.6),
              child: const Center(child: CircularProgressIndicator(color: Colors.black)),
            ),
          ),
        if (_loading && _page > 1)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.black),
          ),
      ],
    );
  }
}