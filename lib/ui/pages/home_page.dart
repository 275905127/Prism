// lib/ui/pages/home_page.dart
import 'dart:convert'; // 🔥 新增：用于 JSON 序列化
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 新增：本地存储

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
    
    // 🔥 初始化时，先加载筛选记录，再请求数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSource(); 
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 🔥 新增：初始化流程 (切换图源时调用)
  Future<void> _initSource() async {
    await _loadFilters(); // 1. 先读本地缓存的筛选设置
    _fetchData(refresh: true); // 2. 再拉取数据
  }

  // 🔥 新增：加载筛选记录
  Future<void> _loadFilters() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Key 格式: filter_prefs_{图源ID}，确保不同图源的筛选互不干扰
      final String? jsonStr = prefs.getString('filter_prefs_${rule.id}');
      
      if (mounted) {
        setState(() {
          if (jsonStr != null && jsonStr.isNotEmpty) {
            _currentFilters = json.decode(jsonStr);
          } else {
            _currentFilters = {}; // 如果没有记录，重置为空
          }
        });
      }
    } catch (e) {
      print("加载筛选记录失败: $e");
    }
  }

  // 🔥 新增：保存筛选记录
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
        _wallpapers.clear(); // 立即清空，提升响应速度感
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
          if (refresh) _wallpapers = data; else _wallpapers.addAll(data);
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
          _saveFilters(newValues); // 🔥 点击应用时保存到本地
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
                // 导入新规则后，重置筛选状态并重新加载
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
                      // 🔥 切换图源时，调用 _initSource 以加载对应的筛选记录
                      // 稍微延迟一下，让 Drawer 关闭动画流畅些
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
      body: _wallpapers.isEmpty && !_loading
          ? Center(child: Text(activeRule == null ? "请先导入图源" : "暂无数据"))
          : MasonryGridView.count(
              controller: _scrollController,
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
