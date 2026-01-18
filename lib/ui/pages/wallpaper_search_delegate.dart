// lib/ui/pages/wallpaper_search_delegate.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/manager/source_manager.dart';
import '../../core/engine/rule_engine.dart';
import '../../core/models/uni_wallpaper.dart';
import 'wallpaper_detail_page.dart';

class WallpaperSearchDelegate extends SearchDelegate {
  final RuleEngine _engine = RuleEngine();
  
  // 覆盖搜索框的提示文字
  @override
  String? get searchFieldLabel => '搜索壁纸...';

  // 1. 搜索框右侧的“清空”按钮
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = ''; // 清空搜索词
            showSuggestions(context); // 回到建议页
          },
        ),
    ];
  }

  // 2. 搜索框左侧的“返回”按钮
  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null), // 关闭搜索
    );
  }

  // 3. 显示搜索结果 (核心逻辑)
  @override
  Widget buildResults(BuildContext context) {
    if (query.isEmpty) return const SizedBox();

    return SearchResultView(query: query, engine: _engine);
  }

  // 4. 显示搜索建议 (这里可以做历史记录，暂时显示简单的引导)
  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(
      color: Theme.of(context).canvasColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('输入关键词搜索\n例如: Anime, Landscape, City', 
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// 提取出来的结果视图 (为了支持 State 刷新和加载更多)
class SearchResultView extends StatefulWidget {
  final String query;
  final RuleEngine engine;

  const SearchResultView({super.key, required this.query, required this.engine});

  @override
  State<SearchResultView> createState() => _SearchResultViewState();
}

class _SearchResultViewState extends State<SearchResultView> {
  final ScrollController _scrollController = ScrollController();
  final List<UniWallpaper> _results = [];
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
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _doSearch(refresh: false);
    }
  }

  Future<void> _doSearch({bool refresh = false}) async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;

    if (_loading) return;

    setState(() {
      _loading = true;
      if (refresh) {
        _page = 1;
        _results.clear();
        _hasMore = true;
      }
    });

    try {
      // 🔥 调用引擎搜索
      final data = await widget.engine.fetch(rule, page: _page, query: widget.query);
      
      if (mounted) {
        setState(() {
          _results.addAll(data);
          if (data.isEmpty) {
             _hasMore = false;
          }  else {
             _page++;
          }
             _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return const Center(child: Text("未找到相关图片"));
    }

    // 复用瀑布流布局
    return MasonryGridView.count(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final paper = _results[index];
        final rule = context.read<SourceManager>().activeRule;
        
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WallpaperDetailPage(
                  wallpaper: paper,
                  headers: rule?.headers,
                ),
              ));
            },
            child: Hero(
              tag: '${paper.id}_search', // 避免 tag 冲突
              child: CachedNetworkImage(
                imageUrl: paper.thumbUrl,
                httpHeaders: rule?.headers,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(color: Colors.grey[200]),
                errorWidget: (c, u, e) => const Icon(Icons.broken_image),
              ),
            ),
          ),
        );
      },
    );
  }
}