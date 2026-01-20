// lib/ui/pages/home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 🔥 确保引入了新库
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/pixiv/pixiv_repository.dart';
import '../../core/pixiv/pixiv_client.dart'; 

import '../widgets/foggy_app_bar.dart';
import '../widgets/filter_sheet.dart';
import 'log_page.dart';
import 'wallpaper_detail_page.dart';
import 'wallpaper_search_delegate.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scrollController = ScrollController();

  List<UniWallpaper> _wallpapers = [];
  bool _loading = false;
  int _page = 1;
  bool _hasMore = true;
  bool _isScrolled = false;

  Map<String, dynamic> _currentFilters = {};
  String? _currentRuleId;

  static String _pixivCookiePrefsKey(String ruleId) => 'pixiv_cookie_$ruleId';
  static const String _kPixivPrefsKey = 'pixiv_preferences_v1';

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
    await _loadPixivPreferences(); 
    await _applyPixivCookieIfNeeded();
    _fetchData(refresh: true);
  }

  Future<void> _loadPixivPreferences() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null || !context.read<WallpaperService>().isPixivRule(rule)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kPixivPrefsKey);
      if (jsonStr != null) {
        final m = jsonDecode(jsonStr);
        context.read<WallpaperService>().setPixivPreferences(
          imageQuality: m['quality'],
          showAi: m['show_ai'],
          mutedTags: (m['muted_tags'] as List?)?.map((e) => e.toString()).toList(),
        );
      }
    } catch (_) {}
  }

  Future<void> _savePixivPreferences() async {
    try {
      final service = context.read<WallpaperService>();
      final p = service.pixivPreferences;
      final m = {
        'quality': p.imageQuality,
        'show_ai': p.showAi,
        'muted_tags': p.mutedTags,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPixivPrefsKey, jsonEncode(m));
    } catch (_) {}
  }

  Future<void> _applyPixivCookieIfNeeded() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;

    if (!context.read<WallpaperService>().isPixivRule(rule)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString(_pixivCookiePrefsKey(rule.id))?.trim() ?? '';
      context.read<WallpaperService>().setPixivCookie(c.isEmpty ? null : c);
    } catch (_) {
    }
  }

  Future<void> _loadFilters() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('filter_prefs_${rule.id}');
      if (!mounted) return;

      setState(() {
        if (jsonStr != null && jsonStr.isNotEmpty) {
          _currentFilters = json.decode(jsonStr);
        } else {
          _currentFilters = {};
        }
      });
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
      final data = await context.read<WallpaperService>().fetch(
        rule,
        page: _page,
        filterParams: _currentFilters,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _wallpapers = data;
          _hasMore = data.isNotEmpty;
          if (_scrollController.hasClients) _scrollController.jumpTo(0);
        } else {
          final newItems = data.where((newItem) {
            return !_wallpapers.any((existing) => existing.id == newItem.id);
          }).toList();

          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            _wallpapers.addAll(newItems);
          }
        }

        if (data.isEmpty) _hasMore = false;
        else _page++;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (refresh) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  void _showFilterSheet() {
    final rule = context.read<SourceManager>().activeRule;
    if (rule == null || rule.filters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("当前图源不支持筛选")));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        filters: rule.filters,
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () {
              if (controller.text.isEmpty) return;
              try {
                context.read<SourceManager>().addRule(controller.text);
                Navigator.pop(ctx);
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

  // 🔥 终极调试版：全程弹窗，解决 Release 包看不到日志的问题
  void _openPixivWebLogin(BuildContext context) async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    String targetUA = PixivClient.kMobileUserAgent;
    if (rule != null && rule.headers != null) {
      final h = rule.headers!;
      final customUA = h['User-Agent'] ?? h['user-agent'];
      if (customUA != null && customUA.trim().isNotEmpty) {
        targetUA = customUA.trim();
      }
    }

    final cookieManager = CookieManager.instance();
    await cookieManager.deleteAllCookies();

    // 辅助函数：显示强制弹窗
    void showMsg(String title, String content) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Text(content, style: const TextStyle(fontSize: 12))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
          ],
        ),
      );
    }

    String? foundCookie;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: const Text('登录 Pixiv', style: TextStyle(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () async {
                // 1. 先弹个 Loading，证明点击生效了
                showDialog(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (c) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  // 🔥🔥🔥 修复：删除了报错的 flush() 调用 🔥🔥🔥
                  // flutter_inappwebview v6 会自动处理同步

                  // 2. 读取 (多域名)
                  final cookiesMain = await cookieManager.getCookies(url: WebUri("https://www.pixiv.net"));
                  final cookiesAcc = await cookieManager.getCookies(url: WebUri("https://accounts.pixiv.net"));
                  
                  // 关闭 Loading
                  if (ctx.mounted) Navigator.pop(ctx); 

                  // 3. 合并检查
                  final allCookies = [...cookiesMain, ...cookiesAcc];
                  final uniqueCookies = <String, Cookie>{};
                  for (var c in allCookies) {
                    uniqueCookies[c.name] = c;
                  }

                  final hasSession = uniqueCookies.containsKey('PHPSESSID');
                  
                  if (hasSession) {
                    final cookieStr = uniqueCookies.values.map((c) => '${c.name}=${c.value}').join('; ');
                    foundCookie = cookieStr;
                    Navigator.pop(ctx); // 关闭 Webview 页面
                  } else {
                    // 💥 失败弹窗：展示所有读到的 Key
                    final names = uniqueCookies.keys.join(', ');
                    showMsg("未检测到 Session", "已读到: [$names]\n\n如果这里只有 device_token 或空，说明还没登录成功，或者网页没加载完。");
                  }
                } catch (e) {
                  // 关闭 Loading
                  if (ctx.mounted) Navigator.pop(ctx);
                  // 💥 异常弹窗
                  showMsg("程序异常", e.toString());
                }
              },
              child: const Text('我已登录', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri('https://accounts.pixiv.net/login')),
          initialSettings: InAppWebViewSettings(
            userAgent: targetUA,
            javaScriptEnabled: true,
            thirdPartyCookiesEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW, 
          ),
        ),
      ),
    );

    if (foundCookie != null && mounted) {
      final manager = context.read<SourceManager>();
      final rule = manager.activeRule;
      if (rule == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final key = _pixivCookiePrefsKey(rule.id);
      
      await prefs.setString(key, foundCookie!);
      context.read<WallpaperService>().setPixivCookie(foundCookie);
      
      showMsg("成功", "登录成功！Cookie 已保存。");
      _fetchData(refresh: true);
    }
  }

  Future<void> _showPixivSettingsDialog() async {
    final manager = context.read<SourceManager>();
    final rule = manager.activeRule;
    if (rule == null) return;
    
    if (!context.read<WallpaperService>().isPixivRule(rule)) return;

    final service = context.read<WallpaperService>();
    final prefs = service.pixivPreferences;
    
    String quality = prefs.imageQuality;
    bool showAi = prefs.showAi;
    final mutedController = TextEditingController(text: prefs.mutedTags.join(' '));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Pixiv 设置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('账户', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(service.hasPixivCookie ? '已设置 Cookie' : '未登录', style: const TextStyle(fontSize: 14)),
                    subtitle: const Text('建议使用 Web 登录自动抓取', style: TextStyle(fontSize: 12)),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openPixivWebLogin(context);
                      },
                      child: const Text('Web 登录'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text('画质偏好', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: quality,
                    isExpanded: true,
                    underline: Container(height: 1, color: Colors.grey[300]),
                    items: const [
                      DropdownMenuItem(value: 'original', child: Text('原图 (Original) - 极耗流量')),
                      DropdownMenuItem(value: 'regular', child: Text('标准 (Regular) - 推荐')),
                      DropdownMenuItem(value: 'small', child: Text('缩略图 (Small) - 极省流')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => quality = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('显示 AI 生成作品', style: TextStyle(fontWeight: FontWeight.bold)),
                      Switch(
                        value: showAi, 
                        activeColor: Colors.black,
                        onChanged: (v) => setState(() => showAi = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('屏蔽标签 (空格分隔)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: mutedController,
                    decoration: const InputDecoration(
                      hintText: '例如: R-18G AI生成 ...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.black),
                onPressed: () {
                  final tags = mutedController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
                  
                  service.setPixivPreferences(
                    imageQuality: quality,
                    showAi: showAi,
                    mutedTags: tags,
                  );
                  _savePixivPreferences();
                  
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存，刷新后生效')));
                  _fetchData(refresh: true);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, String>? _buildSafeImageHeaders({
    required UniWallpaper paper,
    required dynamic activeRule,
  }) {
    final service = context.read<WallpaperService>();
    final base = service.getImageHeaders(activeRule);
    final headers = <String, String>{...?(base ?? const <String, String>{})};

    final u = paper.thumbUrl.trim();
    final isPximg = u.contains('pximg.net');
    if (isPximg) {
      headers.putIfAbsent('Referer', () => 'https://www.pixiv.net/');
      headers.putIfAbsent(
        'User-Agent',
        () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
    }
    if (headers.isEmpty) return null;
    return headers;
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

    final activeRule = context.read<SourceManager>().activeRule;
    final headers = _buildSafeImageHeaders(paper: paper, activeRule: activeRule);

    final imageWidget = CachedNetworkImage(
      imageUrl: paper.thumbUrl,
      httpHeaders: headers,
      fit: BoxFit.fitWidth,
      placeholder: (c, u) => Container(
        color: Colors.grey[100],
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
        ),
      ),
      errorWidget: (c, u, e) => Container(
        color: Colors.grey[50],
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, color: Colors.grey, size: 30),
            const SizedBox(height: 6),
            const Text('图片加载失败', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );

    final List<Widget> badges = [];
    if (paper.isUgoira) {
      badges.add(Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
        child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
      ));
    }
    if (paper.isAi) {
      badges.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
        child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
      ));
    }

    final content = Container(
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
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                ),
              ),
            if (badges.isNotEmpty)
              Positioned(
                top: 6,
                right: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: badges),
              ),
          ],
        ),
      ),
    );

    if (paper.aspectRatio > 0) {
      return AspectRatio(aspectRatio: paper.aspectRatio, child: content);
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<SourceManager>();
    final activeRule = manager.activeRule;
    final hasFilters = activeRule != null && activeRule.filters.isNotEmpty;

    if (activeRule != null && activeRule.id != _currentRuleId) {
      _currentRuleId = activeRule.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initSource();
      });
    }

    final detailHeaders = context.read<WallpaperService>().getImageHeaders(activeRule);
    
    final showPixivSettings = context.read<WallpaperService>().isPixivRule(activeRule);

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

            if (showPixivSettings)
              ListTile(
                leading: const Icon(Icons.settings_applications, color: Colors.black),
                title: const Text('Pixiv 设置', style: TextStyle(color: Colors.black)),
                subtitle: const Text('登录 / 画质 / 屏蔽', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  _showPixivSettingsDialog();
                },
              ),

            ListTile(
              leading: const Icon(Icons.add, color: Colors.black),
              title: const Text('导入规则', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                _showImportDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined, color: Colors.black),
              title: const Text('日志', style: TextStyle(color: Colors.black)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LogPage()));
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
                      Icon(Icons.photo_library_outlined, size: 60, color: Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        activeRule == null ? "请先导入图源" : (_hasMore ? "暂无数据" : "没有更多图片了"),
                        style: TextStyle(color: Colors.grey[400]),
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
                  itemCount: _wallpapers.length + (_hasMore ? 0 : 1),
                  itemBuilder: (context, index) {
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
                        MaterialPageRoute(
                          builder: (_) => WallpaperDetailPage(
                            wallpaper: paper,
                            headers: detailHeaders,
                          ),
                        ),
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
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.black),
            ),
        ],
      ),
    );
  }
}
