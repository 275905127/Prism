import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/manager/source_manager.dart';
import '../../core/engine/rule_engine.dart';
import '../../core/models/uni_wallpaper.dart';
import '../widgets/foggy_app_bar.dart'; // 🔥 引入我们刚写的组件
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
    // 监听滚动距离，更新 AppBar 状态
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
      if (mounted) {
        setState(() => _loading = false);
        if (refresh) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showImportDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('导入图源规则'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '在此粘贴 JSON 内容...',
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
          ),
          style: const TextStyle(fontSize: 12, fontFamily: "monospace"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Colors.grey))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () {
              if (controller.text.isEmpty) return;
              try {
                context.read<SourceManager>().addRule(controller.text);
                Navigator.pop(ctx);
                _fetchData(refresh: true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 格式错误')));
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    final activeRule = manager.activeRule;

    return Scaffold(
      extendBodyBehindAppBar: true, // 🔥 让内容延伸到 AppBar 下方
      appBar: FoggyAppBar( // 🔥 使用封装好的组件
        isScrolled: _isScrolled,
        title: Text(
          activeRule?.name ?? 'Prism',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 48, color: Colors.black),
                    SizedBox(height: 10),
                    Text('Prism', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: manager.rules.length,
                itemBuilder: (context, index) {
                  final rule = manager.rules[index];
                  final isSelected = rule.id == activeRule?.id;
                  return ListTile(
                    title: Text(rule.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    leading: isSelected 
                        ? const Icon(Icons.circle, color: Colors.black, size: 10)
                        : const Icon(Icons.circle_outlined, color: Colors.grey, size: 10),
                    onTap: () {
                      manager.setActive(rule.id);
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 200), () => _fetchData(refresh: true));
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                      onPressed: () => manager.deleteRule(rule.id),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Colors.black12),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.black),
              title: const Text('导入规则', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                _showImportDialog(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: _wallpapers.isEmpty && !_loading
          ? Center(child: Text(activeRule == null ? "请先导入图源" : "暂无数据"))
          : MasonryGridView.count(
              controller: _scrollController,
              // 🔥 关键：顶部留出 100 的距离给 AppBar，否则第一排会被挡住
              padding: const EdgeInsets.only(top: 100, left: 12, right: 12, bottom: 12),
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
                      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: paper.thumbUrl, 
                          httpHeaders: activeRule?.headers,
                          fit: BoxFit.cover,
                          placeholder: (c,u) => Container(color: Colors.grey[200]),
                          errorWidget: (c,u,e) => const Icon(Icons.broken_image, color: Colors.grey),
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
