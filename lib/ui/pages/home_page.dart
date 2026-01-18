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
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (refresh) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载失败: $e')),
          );
        }
      }
    }
  }

  void _showImportDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white, // 弹窗背景白
        surfaceTintColor: Colors.white, // 去掉 Material3 的混色
        title: const Text('导入图源规则'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          cursorColor: Colors.black, // 光标黑
          decoration: const InputDecoration(
            hintText: '在此粘贴 JSON 内容...',
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.black), // 选中框黑
            ),
          ),
          style: const TextStyle(fontSize: 12, fontFamily: "monospace"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('取消', style: TextStyle(color: Colors.grey))
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black, // 按钮黑
              foregroundColor: Colors.white, // 文字白
            ),
            onPressed: () {
              if (controller.text.isEmpty) return;
              try {
                context.read<SourceManager>().addRule(controller.text);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ 导入成功！')),
                );
                _fetchData(refresh: true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('❌ 格式错误: $e')),
                );
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
      // 背景色已经在 main.dart 全局设置，这里不用重复设
      appBar: AppBar(
        title: Text(
          activeRule?.name ?? 'Prism',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () {
              showSearch(
                context: context,
                delegate: WallpaperSearchDelegate(),
              );
            },
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
            // 🔥 Drawer 头部改为纯白
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.black12)), // 底部细灰线
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 48, color: Colors.black),
                    SizedBox(height: 10),
                    Text('Prism 棱镜', 
                      style: TextStyle(
                        color: Colors.black, 
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      )),
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
                    title: Text(
                      rule.name,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.black, // 字体始终为黑
                      ),
                    ),
                    subtitle: Text(rule.id, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    leading: isSelected 
                        ? const Icon(Icons.circle, color: Colors.black, size: 10) // 选中实心黑点
                        : const Icon(Icons.circle_outlined, color: Colors.grey, size: 10),
                    onTap: () {
                      manager.setActive(rule.id);
                      Navigator.pop(context);
                      Future.delayed(const Duration(milliseconds: 200), () {
                        _fetchData(refresh: true);
                      });
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
              leading: const Icon(Icons.add_circle_outline, color: Colors.black),
              title: const Text('导入规则 (JSON)', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                _showImportDialog(context);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: Stack(
        children: [
          _wallpapers.isEmpty && !_loading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        activeRule == null ? "请先导入图源" : "暂无数据",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : MasonryGridView.count(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  itemCount: _wallpapers.length,
                  itemBuilder: (context, index) {
                    final paper = _wallpapers[index];
                    return Card(
                      elevation: 0, // 去掉阴影
                      // 使用极淡的灰，或者你可以改成 Colors.white
                      color: Theme.of(context).cardColor, 
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WallpaperDetailPage(
                                wallpaper: paper,
                                headers: activeRule?.headers,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: paper.aspectRatio,
                              child: Hero(
                                tag: paper.id,
                                child: CachedNetworkImage(
                                  imageUrl: paper.thumbUrl,
                                  httpHeaders: activeRule?.headers,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[200]),
                                  errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          
          // 底部加载条 (黑色)
          if (_loading && _wallpapers.isNotEmpty)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Colors.black, // 🔥 加载条变黑
              ),
            ),
            
          // 中心加载圈 (黑色)
          if (_loading && _wallpapers.isEmpty)
            const Center(child: CircularProgressIndicator(color: Colors.black)),
        ],
      ),
    );
  }
}
