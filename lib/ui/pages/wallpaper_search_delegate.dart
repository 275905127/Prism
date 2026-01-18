import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../core/manager/source_manager.dart';
import '../../core/engine/rule_engine.dart';
import '../../core/models/uni_wallpaper.dart';
import 'wallpaper_detail_page.dart';

class WallpaperSearchDelegate extends SearchDelegate {
  final RuleEngine _engine = RuleEngine();

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
        IconButton(icon: const Icon(Icons.clear, color: Colors.black), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => close(context, null));
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
  final RuleEngine _engine = RuleEngine();
  final ScrollController _scrollController = ScrollController();
  List<UniWallpaper> _wallpapers = [];
  bool _loading = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _doSearch();
  }

  void _onScroll() {
    if (_loading) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _doSearch(nextPage: true);
    }
  }

  Future<void> _doSearch({bool nextPage = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final manager = context.read<SourceManager>();
      if (manager.activeRule == null) return;
      final data = await _engine.fetch(manager.activeRule!, page: _page, query: widget.query);
      if (mounted) {
        setState(() {
          if (!nextPage) _wallpapers = data; else _wallpapers.addAll(data);
          _page++;
          _loading = false;
        });
      }
    } catch (e) {
      if(mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    return MasonryGridView.count(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: _wallpapers.length,
      itemBuilder: (context, index) {
        final paper = _wallpapers[index];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WallpaperDetailPage(wallpaper: paper, headers: manager.activeRule?.headers))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(imageUrl: paper.thumbUrl, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}
