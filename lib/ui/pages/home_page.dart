// lib/ui/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/manager/source_manager.dart';
import '../../core/engine/rule_engine.dart';
import '../../core/models/uni_wallpaper.dart';
import 'wallpaper_detail_page.dart';
import 'wallpaper_search_delegate.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RuleEngine _engine = RuleEngine();
  final ScrollController _scrollController = ScrollController();
  
  List<UniWallpaper> _wallpapers = [];
  bool _loading = false;
  int _page = 1;
  bool _hasMore = true;
  
  // 🔥 新增：滚动状态
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData(refresh: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 🔥 监听滚动距离，更新 AppBar 状态
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 0;
    if (isScrolled != _isScrolled) {
      setState(() => _isScrolled = isScrolled);
    }

    if (_loading || !_hasMore) return;
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _fetchData(refresh: false);
    }
  }

  // ... _fetchData 和 _showImportDialog 代码保持不变 ...
  Future<void> _fetchData({bool refresh = false}) async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;
    if (_loading) return;
    setState(() {
      _loading = true;
      if (refresh) {
        _page = 1;
        _hasMore = true;
        if (_wallpapers.isEmpty) _loading = true; 
      }
    });
    try {
      final data = await _engine.fetch(rule, page: _page);
      if (mounted) {
        setState(() {
          if (refresh) _wallpapers = data; else _wallpapers.addAll(data);
          if (data.isEmpty) _hasMore = false; else _page++;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showImportDialog(BuildContext context) {
    // ... (这里代码太长省略，保持原样即可，如果你需要我可以补全) ...
    // 为了节省篇幅，假设你保留了之前的 import dialog 逻辑
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('导入图源规则'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '在此粘贴 JSON...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () {
              if (controller.text.isEmpty) return;
              try {
                context.read<SourceManager>().addRule(controller.text);
                Navigator.pop(ctx);
                _fetchData(refresh: true);
              } catch (e) {}
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  // 🔥 核心：构建雾化渐变背景
  Widget _buildFogBackground(Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            baseColor.withOpacity(0.94),
            baseColor.withOpacity(0.94),
            baseColor.withOpacity(0.90),
            baseColor.withOpacity(0.75),
            baseColor.withOpacity(0.50),
            baseColor.withOpacity(0.20),
            baseColor.withOpacity(0.0),
          ],
          stops: const [0.0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    final activeRule = manager.activeRule;

    return Scaffold(
      extendBodyBehindAppBar: true, // 🔥 让内容延伸到 AppBar 下方
      appBar: AppBar(
        title: Text(
          activeRule?.name ?? 'Prism',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        // 🔥 使用你要求的参数
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: AnimatedOpacity(
          opacity: _isScrolled ? 1.0 : 0.0, // 滚动时显示雾化，不滚动透明
          duration: const Duration(milliseconds: 200),
          child: _buildFogBackground(Colors.white), // 基色为白
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: WallpaperSearchDelegate()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchData(refresh: true),
          ),
        ],
      ),
      drawer: Drawer(
        // ... Drawer 代码保持不变 ...
        child: Column(children: [
           const DrawerHeader(child: Center(child: Text("Prism", style: TextStyle(fontSize: 24)))),
           Expanded(child: ListView.builder(
             itemCount: manager.rules.length,
             itemBuilder: (ctx, i) => ListTile(
               title: Text(manager.rules[i].name),
               onTap: () {
                 manager.setActive(manager.rules[i].id);
                 Navigator.pop(context);
                 _fetchData(refresh: true);
               },
             )
           )),
           ListTile(
             title: const Text("导入规则"),
             onTap: () => _showImportDialog(context),
           )
        ]),
      ),
      body: _wallpapers.isEmpty && !_loading
          ? const Center(child: Text("暂无数据")) // 简化占位
          : MasonryGridView.count(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 100, left: 12, right: 12, bottom: 12), // 🔥 Top padding 让出 AppBar 高度
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              itemCount: _wallpapers.length,
              itemBuilder: (context, index) {
                final paper = _wallpapers[index];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => WallpaperDetailPage(wallpaper: paper, headers: activeRule?.headers))
                  ),
                  child: AspectRatio(
                    aspectRatio: paper.aspectRatio,
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: paper.thumbUrl, 
                          httpHeaders: activeRule?.headers,
                          fit: BoxFit.cover
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
