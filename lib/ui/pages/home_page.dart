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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSource(); 
    });
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
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          } else {
            _wallpapers.addAll(data);
          }
          if (data.isEmpty) _hasMore = false; else _page++;
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
                setState(() => _currentFilters = {}); 
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

  Widget _buildWallpaperItem(UniWallpaper paper) {
    Color? borderColor;
    if (paper.grade != null) {
      final g = paper.grade!.toLowerCase();
      if (g == 'nsfw') {
        borderColor = const Color(0xFFFF3B30); // iOS 风格红
      } else if (g == 'sketchy') {
        borderColor = const Color(0xFFFFCC00); // Wallhaven 黄
      }
    }

    // 🔥 定义样式常量
    const double kOuterRadius = 8.0; // 外圆角加大到 8
    const double kBorderWidth = 1.0; // 边框变细为 1
    // 🔥 精确计算内圆角，消除空隙
    final double kInnerRadius = borderColor != null ? (kOuterRadius - kBorderWidth) : kOuterRadius;

    Widget imageWidget = CachedNetworkImage(
      imageUrl: paper.thumbUrl,
      httpHeaders: context.read<SourceManager>().activeRule?.headers,
      fit: BoxFit.fitWidth, 
      placeholder: (c, u) => Container(
        color: Colors.grey[100], // 占位符颜色调浅一点
        height: paper.aspectRatio > 0 ? null : 200, 
      ),
      errorWidget: (c, u, e) => Container(
        color: Colors.grey[50],
        height: 150,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 30),
      ),
    );

    // 容器
    Widget content = Container(
      decoration: BoxDecoration(
        color: Colors.white, // 强制纯白底色，确保透明图片也有底
        borderRadius: BorderRadius.circular(kOuterRadius),
        // 🔥 新增：质感阴影
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06), // 极淡的阴影
            blurRadius: 10, // 柔和扩散
            offset: const Offset(0, 4), // 向下偏移，营造浮起感
            spreadRadius: 0,
          ),
        ],
        // 🔥 更新：细边框
        border: borderColor != null 
            ? Border.all(color: borderColor, width: kBorderWidth) 
            : null,
      ),
      child: ClipRRect(
        // 🔥 更新：使用精确计算的内圆角
        borderRadius: BorderRadius.circular(kInnerRadius),
        child: imageWidget,
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
                      Future.delayed(const Duration(milliseconds: 150), () {
                        _initSource();
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
          _wallpapers.isEmpty && !_loading
              ? Center(child: Text(activeRule == null ? "请先导入图源" : "暂无数据"))
              : MasonryGridView.count(
                  controller: _scrollController,
                  // 保持紧凑间距
                  padding: const EdgeInsets.only(top: 100, left: 6, right: 6, bottom: 6),
                  crossAxisCount: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  itemCount: _wallpapers.length,
                  itemBuilder: (context, index) {
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
