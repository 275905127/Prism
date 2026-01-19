// lib/ui/pages/wallpaper_search_delegate.dart
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart'; // 引入 Service
import 'wallpaper_detail_page.dart';

class WallpaperSearchDelegate extends SearchDelegate {
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
    if (query.trim().isEmpty) return const SizedBox();
    return _SearchResults(query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(color: Colors.white);
  }
}

class _SearchResults extends StatefulWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  // 🔥 删除：不再直接持有 Engine/Repo
  // final RuleEngine _engine = RuleEngine();
  // final PixivRepository _pixivRepo = PixivRepository();

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

  Future<void> _doSearch({required bool refresh}) async {
    if (_loading) return;

    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
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
      if (q.isEmpty) {
        if (!mounted) return;
        setState(() {
          _wallpapers = [];
          _loading = false;
          _hasMore = false;
        });
        return;
      }

      // 🔥 核心修改：统一走 Service 调用
      final List<UniWallpaper> data = await context.read<WallpaperService>().fetch(
        rule,
        page: _page,
        query: q,
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    final rule = manager.activeRule;

    // 🔥 核心修改：统一走 Service 获取 Headers
    final headers = context.read<WallpaperService>().getImageHeaders(rule);

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
                  imageUrl: paper.thumbUrl,
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
