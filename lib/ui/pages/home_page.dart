// lib/ui/pages/home_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/pixiv/pixiv_client.dart';
import '../../core/utils/prism_logger.dart';

import '../controllers/home_controller.dart';
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

  // 避免重复弹 SnackBar
  String _lastShownError = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Pixiv Preferences ----------
  Future<void> _savePixivPreferences() async {
    try {
      await context.read<WallpaperService>().persistPixivPreferences();
    } catch (_) {}
  }

  // ---------- UI helpers ----------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------- Filter sheet ----------
  void _showFilterSheet() {
    final rule = context.read<SourceManager>().activeRule;
    if (rule == null || rule.filters.isEmpty) {
      _snack("当前图源不支持筛选");
      return;
    }

    final home = context.read<HomeController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        filters: rule.filters,
        currentValues: home.currentFilters,
        onApply: (newValues) {
          home.applyFilters(newValues);
        },
      ),
    );
  }

  // ---------- Import rule ----------
  void _showImportDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        title: const Text('导入图源规则'),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: '在此粘贴 JSON 内容...',
              filled: true,
              fillColor: const Color(0xFFF3F3F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 12, fontFamily: "monospace"),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (controller.text.isEmpty) return;
              try {
                context.read<SourceManager>().addRule(controller.text);
                Navigator.pop(ctx);
              } catch (_) {
                _snack('JSON 格式错误');
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  // ---------- Pixiv Web Login ----------
  void _openPixivWebLogin(BuildContext context) async {
    // ✅ 必须从 Provider 取全局 logger，避免你本地 new 导致日志系统割裂
    final PrismLogger logger = context.read<PrismLogger>();

    final sourceManager = context.read<SourceManager>();
    final wallpaperService = context.read<WallpaperService>();
    final rule = sourceManager.activeRule;

    String targetUA = PixivClient.kMobileUserAgent;
    if (rule != null && rule.headers != null) {
      final h = rule.headers!;
      final customUA = h['User-Agent'] ?? h['user-agent'];
      if (customUA != null && customUA.trim().isNotEmpty) {
        targetUA = customUA.trim();
      }
    }

    final cookieManager = CookieManager.instance();
    logger.log(
      'Pixiv web login opened (UI) UA=${targetUA.length > 60 ? '${targetUA.substring(0, 60)}...' : targetUA}',
    );

    await cookieManager.deleteAllCookies();
    logger.log('Pixiv webview cookies cleared (UI)');

    void snack(BuildContext ctx, String msg) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }

    Future<String?> checkCookies() async {
      final cookiesMain = await cookieManager.getCookies(url: WebUri("https://www.pixiv.net"));
      final cookiesAcc = await cookieManager.getCookies(url: WebUri("https://accounts.pixiv.net"));

      final allCookies = [...cookiesMain, ...cookiesAcc];
      final uniqueCookies = <String, Cookie>{};
      for (final c in allCookies) {
        uniqueCookies[c.name] = c;
      }

      if (uniqueCookies.containsKey('PHPSESSID')) {
        return uniqueCookies.values.map((c) => '${c.name}=${c.value}').join('; ');
      }
      return null;
    }

    Future<void> logCookieNamesSnapshot() async {
      try {
        final cookiesMain = await cookieManager.getCookies(url: WebUri("https://www.pixiv.net"));
        final cookiesAcc = await cookieManager.getCookies(url: WebUri("https://accounts.pixiv.net"));
        final mainNames = cookiesMain.map((c) => c.name).toSet().toList()..sort();
        final accNames = cookiesAcc.map((c) => c.name).toSet().toList()..sort();
        logger.log('Pixiv cookie snapshot: pixiv.net=[${mainNames.join(', ')}]');
        logger.log('Pixiv cookie snapshot: accounts.pixiv.net=[${accNames.join(', ')}]');
      } catch (e, st) {
        logger.log('Pixiv cookie snapshot failed: $e\n$st');
      }
    }

    bool sheetDetected = false;
    String sheetCookie = '';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> markDetected(String cookie, {required String by}) async {
            sheetCookie = cookie.trim();
            sheetDetected = sheetCookie.isNotEmpty;

            logger.log('Pixiv cookie detected ($by) len=${sheetCookie.length}');
            await logCookieNamesSnapshot();

            if (ctx.mounted) {
              setModalState(() {});
              snack(ctx, '已检测到 Cookie（$by），请点右上角「保存」');
            }
          }

          Future<void> manualCheck() async {
            logger.log('Pixiv manual check triggered');
            try {
              final cookieStr = await checkCookies();
              if (cookieStr != null) {
                await markDetected(cookieStr, by: 'manual');
              } else {
                logger.log('Pixiv manual check: PHPSESSID not found');
                await logCookieNamesSnapshot();
                snack(ctx, '未检测到 PHPSESSID（已写入日志页）');
              }
            } catch (e, st) {
              logger.log('Pixiv manual check exception: $e\n$st');
              snack(ctx, '检测异常：$e');
            }
          }

          /// ✅ 修复点：
          /// - pop sheet 后的 refresh 延迟到下一帧，规避生命周期竞态导致的 null-assert 崩溃
          /// - 所有 catch 记录 stacktrace，便于 CI 精确定位
          Future<void> doSave() async {
            if (saving) return;

            final cookie = sheetCookie.trim();
            if (cookie.isEmpty) {
              logger.log('Pixiv save blocked (UI): cookie empty');
              snack(ctx, 'Cookie 为空，无法保存');
              return;
            }

            final active = sourceManager.activeRule;
            if (active == null) {
              logger.log('Pixiv save failed (UI): activeRule null');
              snack(ctx, '保存失败：activeRule 为空');
              return;
            }

            saving = true;
            if (ctx.mounted) setModalState(() {});

            logger.log('Pixiv save stage entered (UI) cookieLen=${cookie.length} rule=${active.id}');

            try {
              // 1) 通过 Service 保存（包含 prefs 保存 + repo 注入）
              await wallpaperService.setPixivCookieForRule(active.id, cookie);
              logger.log('Pixiv cookie persisted via WallpaperService (UI) len=${cookie.length}');

              // 2) 写入 rule.headers 并持久化 rules_v2
              await sourceManager.updateRuleHeader(active.id, 'Cookie', cookie);
              logger.log('Pixiv cookie written into rule.headers (UI) rule=${active.id}');

              snack(ctx, '已保存，正在刷新…');

              // ✅ 先关闭 sheet（避免 ctx/context 生命周期导致的空指针）
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.pop(ctx);
              }

              // ✅ 关键修复：延迟到下一帧再 refresh，避免 pop + Provider rebuild 竞态触发空断言
              if (!mounted) {
                logger.log('Pixiv refresh skipped (UI): HomePage unmounted');
                return;
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                () async {
                  try {
                    if (!mounted) return;

                    await context.read<HomeController>().refresh();

                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    }

                    logger.log('Pixiv refresh done (UI)');
                  } catch (e, st) {
                    logger.log('Pixiv refresh failed (UI): $e\n$st');
                    if (mounted) {
                      _snack('已保存 Cookie，但刷新失败：$e');
                    }
                  }
                }();
              });

              logger.log('Pixiv save success (UI)');
            } catch (e, st) {
              logger.log('Pixiv save failed (UI): $e\n$st');
              snack(ctx, '保存失败：$e');
              saving = false;
              if (ctx.mounted) setModalState(() {});
            }
          }

          final bool saveEnabled = sheetDetected && sheetCookie.isNotEmpty;

          return Scaffold(
            appBar: AppBar(
              title: const Text('登录 Pixiv', style: TextStyle(fontSize: 16)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: saving
                    ? null
                    : () {
                        logger.log('Pixiv web login closed by user (UI) detected=$sheetDetected');
                        Navigator.pop(ctx);
                      },
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : manualCheck,
                  child: const Text('我已登录', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: FilledButton(
                    onPressed: (!saveEnabled || saving) ? null : doSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: saveEnabled ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
                  ),
                  child: Text(
                    saveEnabled
                        ? '已检测到 Cookie：请点击右上角「保存」。'
                        : '登录完成后等待自动检测，或点右上角「我已登录」手动检测。检测结果会写入日志页。',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri('https://accounts.pixiv.net/login')),
                    initialSettings: InAppWebViewSettings(
                      userAgent: targetUA,
                      javaScriptEnabled: true,
                      sharedCookiesEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    ),
                    onLoadStop: (controller, url) async {
                      try {
                        final urlStr = url?.toString() ?? '';
                        logger.log('Pixiv web onLoadStop url=$urlStr');

                        if (urlStr.contains('accounts.pixiv.net')) return;

                        if (urlStr.contains('pixiv.net') && !urlStr.contains('login')) {
                          logger.log('Pixiv auto check started');

                          const int maxTry = 12;
                          for (int i = 0; i < maxTry; i++) {
                            final cookieStr = await checkCookies();
                            if (cookieStr != null) {
                              await markDetected(cookieStr, by: 'auto');
                              return;
                            }
                            await Future.delayed(const Duration(milliseconds: 500));
                          }

                          logger.log('Pixiv auto check: PHPSESSID not found after retries');
                          await logCookieNamesSnapshot();
                          if (ctx.mounted) snack(ctx, '自动检测失败（已写入日志页），可点击「我已登录」手动检测');
                        }
                      } catch (e, st) {
                        logger.log('Pixiv auto check exception: $e\n$st');
                        if (ctx.mounted) snack(ctx, '自动检测异常：$e');
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    logger.log('Pixiv web login sheet closed (UI)');
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
            backgroundColor: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 30),
            title: const Text('Pixiv 设置'),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('账户', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        service.hasPixivCookie ? '已设置 Cookie' : '未登录',
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text('建议使用 Web 登录自动抓取', style: TextStyle(fontSize: 12)),
                      trailing: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
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
                      decoration: InputDecoration(
                        hintText: '例如: R-18G AI生成 ...',
                        filled: true,
                        fillColor: const Color(0xFFF3F3F3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final tags =
                      mutedController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

                  service.setPixivPreferences(
                    imageQuality: quality,
                    showAi: showAi,
                    mutedTags: tags,
                  );
                  await _savePixivPreferences();

                  if (ctx.mounted) Navigator.pop(ctx);

                  _snack('设置已保存，刷新后生效');

                  await context.read<HomeController>().refresh();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- Grid helpers ----------

  Widget _buildWallpaperItem({
    required BuildContext context,
    required UniWallpaper paper,
    required Map<String, String>? baseHeaders,
    required int memCacheWidth,
  }) {
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

    final rule = context.read<SourceManager>().activeRule;
    final headers = context.read<WallpaperService>().imageHeadersFor(wallpaper: paper, rule: rule);

    final imageWidget = CachedNetworkImage(
      imageUrl: paper.thumbUrl,
      httpHeaders: headers,
      fit: BoxFit.fitWidth,
      memCacheWidth: memCacheWidth,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
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
          children: const [
            Icon(Icons.broken_image, color: Colors.grey, size: 30),
            SizedBox(height: 6),
            Text('图片加载失败', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );

    final List<Widget> badges = [];
    if (paper.isUgoira) {
      badges.add(
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
          child: const Text('GIF', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
      );
    }
    if (paper.isAi) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.7), borderRadius: BorderRadius.circular(4)),
          child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final content = RepaintBoundary(
      child: Container(
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
    final home = context.watch<HomeController>();

    final activeRule = manager.activeRule;
    final hasFilters = activeRule != null && activeRule.filters.isNotEmpty;

    // 统一从 Service 取 headers：detail 与 thumb 分开处理（thumb 可能需要补 referer/ua）
    final baseHeaders = context.read<WallpaperService>().getImageHeaders(activeRule);
    final showPixivSettings = context.read<WallpaperService>().isPixivRule(activeRule);

    // 统一错误出口：HomeController 不触达 BuildContext
    final err = home.lastError ?? '';
    if (err.isNotEmpty && err != _lastShownError) {
      _lastShownError = err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(err);
      });
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final width = MediaQuery.of(context).size.width;
    final memCacheWidth = ((width / 2) * dpr).round().clamp(200, 1200);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: FoggyAppBar(
        isScrolled: home.isScrolled,
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
              icon: Icon(Icons.tune, color: home.currentFilters.isNotEmpty ? Colors.black : Colors.grey[700]),
              onPressed: _showFilterSheet,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await home.refresh();
              if (!mounted) return;
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
        ],
      ),
      drawer: Drawer(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
        ),
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
                    title: Text(
                      rule.name,
                      style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    ),
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
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis != Axis.vertical) return false;
          home.onScroll(
            offset: n.metrics.pixels,
            maxScrollExtent: n.metrics.maxScrollExtent,
          );
          return false;
        },
        child: Stack(
          children: [
            home.wallpapers.isEmpty && !home.loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text(
                          activeRule == null ? "请先导入图源" : (home.hasMore ? "暂无数据" : "没有更多图片了"),
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
                    itemCount: home.wallpapers.length + (home.hasMore ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == home.wallpapers.length) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          child: Text("— End —", style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                        );
                      }

                      final paper = home.wallpapers[index];
                      return GestureDetector(
                        key: ValueKey('${paper.sourceId}::${paper.id}'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WallpaperDetailPage(
                              wallpaper: paper,
                            ),
                          ),
                        ),
                        child: _buildWallpaperItem(
                          context: context,
                          paper: paper,
                          baseHeaders: baseHeaders,
                          memCacheWidth: memCacheWidth,
                        ),
                      );
                    },
                  ),
            if (home.loading && home.page == 1)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.6),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  ),
                ),
              ),
            if (home.loading && home.page > 1)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.black),
              ),
          ],
        ),
      ),
    );
  }
}