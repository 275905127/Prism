// lib/ui/pages/home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/manager/source_manager.dart';
import '../../core/engine/rule_engine.dart';
import '../../core/models/uni_wallpaper.dart';
import '../widgets/foggy_app_bar.dart';
import '../widgets/filter_sheet.dart';
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
  bool _isScrolled = false;

  Map<String, dynamic> _currentFilters = {};

  // 用来记录当前正在展示的图源ID
  String? _currentRuleId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSource() async {
    await _loadFilters(); 
    _fetchData(refresh: true); 
  }

  Future<void> _loadFilters() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('filter_prefs_${rule.id}');
      if (mounted) {
        setState(() {
          if (jsonStr != null && jsonStr.isNotEmpty) {
            _currentFilters = json.decode(jsonStr);
          } else {
            _currentFilters = {};
          }
        });
      }
    } catch (e) {
      print("加载筛选记录失败: $e");
    }
  }

  Future<void> _saveFilters(Map<String, dynamic> filters) async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (filters.isEmpty) {
        await prefs.remove('filter_prefs_${rule.id}');
      } else {
        await prefs.setString('filter_prefs_${rule.id}', json.encode(filters));
      }
    } catch (e) {
      print("保存筛选记录失败: $e");
    }
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 0;
    if (isScrolled != _isScrolled) setState(() => _isScrolled = isScrolled);

    if (_loading || !_hasMore) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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
      }
    });

    try {
      final data = await _engine.fetch(
        rule, 
        page: _page,
        filterParams: _currentFilters,
      );
      
      if (mounted) {
        setState(() {
          if (refresh) {
            _wallpapers = data;
            // 刷新时，如果有数据则重置 hasMore，否则说明是空源
            _hasMore = data.isNotEmpty; 
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          } else {
            // 🔥 核心修复：去重逻辑
            // 筛选出 _wallpapers 里不存在的新图片
            final newItems = data.where((newItem) {
              return !_wallpapers.any((existing) => existing.id == newItem.id);
            }).toList();

            if (newItems.isEmpty) {
              // 🔥 如果接口返回了数据，但全是重复的，说明到底了，停止加载
              _hasMore = false;
            } else {
              _wallpapers.addAll(newItems);
            }
          }
          
          // 如果本次返回的数据本身就很少（比如小于一页），也说明没更多了
          if (data.isEmpty) _hasMore = false; 
          else _page++;
          
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (refresh) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  void _showFilterSheet() {
    final rule = context.read<SourceManager>().activeRule;
    if (rule == null || rule.filters == null || rule.filters!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("当前图源不支持筛选")));
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        filters: rule.filters!,
        currentValues: _currentFilters,
        onApply: (newValues) {
          setState(() => _currentFilters = newValues);
          _saveFilters(newValues);
          _fetchData(refresh: true);
        },
      ),
    );
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
                // 导入成功不需手动刷新，build监听器会处理
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

  Widget _buildWallpaperItem(UniWallpaper paper) {
    Color? borderColor;
    if (paper.grade != null) {
      final g = paper.grade!.toLowerCase();
      if (g == 'nsfw') {
        borderColor = const Color(0xFFFF453A).withOpacity(0.3); 
      } else if (g == 'sketchy') {
        borderColor = const Color(0xFFFFD60A).withOpacity(0.4); 
      }
    }

    const double kRadius = 6.0;
    const double kBorderWidth = 1.5; 

    Widget imageWidget = CachedNetworkImage(
      imageUrl: paper.thumbUrl,
      httpHeaders: context.read<SourceManager>().activeRule?.headers,
      fit: BoxFit.fitWidth, 
      placeholder: (c, u) => Container(
        color: Colors.grey[100], 
        height: paper.aspectRatio > 0 ? null : 200, 
      ),
      errorWidget: (c, u, e) => Container(
        color: Colors.grey[50],
        height: 150,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 30),
      ),
    );

    Widget content = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06), 
            blurRadius: 8,
            offset: const Offset(0, 3), 
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            imageWidget,
            if (borderColor != null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(
                      color: borderColor, 
                      width: kBorderWidth, 
                      strokeAlign: BorderSide.strokeAlignInside 
                    ),
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (paper.aspectRatio > 0) {
      return AspectRatio(aspectRatio: paper.aspectRatio, child: content);
    } else {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    final activeRule = manager.activeRule;
    final hasFilters = activeRule?.filters != null && activeRule!.filters!.isNotEmpty;

    if (activeRule != null && activeRule.id != _currentRuleId) {
      _currentRuleId = activeRule.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initSource();
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FoggyAppBar(
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
          if (hasFilters) 
            IconButton(
              icon: Icon(Icons.tune, color: _currentFilters.isNotEmpty ? Colors.black : Colors.grey[700]),
              onPressed: _showFilterSheet,
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
      body: Stack(
        children: [
          // 空状态
          _wallpapers.isEmpty && !_loading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 60, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        activeRule == null ? "请先导入图源" : (_hasMore ? "暂无数据" : "没有更多图片了"), 
                        style: TextStyle(color: Colors.grey[400])
                      ),
                    ],
                  ),
                )
              : MasonryGridView.count(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 100, left: 6, right: 6, bottom: 6),
                  crossAxisCount: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  itemCount: _wallpapers.length + (_hasMore ? 0 : 1), // 如果到底了，多留一个位置给底栏
                  itemBuilder: (context, index) {
                    // 底部文字提示
                    if (index == _wallpapers.length) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: Text("— End —", style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                      );
                    }
                    
                    final paper = _wallpapers[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => WallpaperDetailPage(wallpaper: paper, headers: activeRule?.headers))
                      ),
                      child: _buildWallpaperItem(paper),
                    );
                  },
                ),
          
          if (_loading && _page == 1)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.black),
                ),
              ),
            ),
          
          if (_loading && _page > 1)
             const Positioned(
              left: 0, right: 0, bottom: 0,
              child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.black),
            ),
        ],
      ),
    );
  }
}
