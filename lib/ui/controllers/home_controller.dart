// lib/ui/controllers/home_controller.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/manager/source_manager.dart';
import '../../core/models/source_rule.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/utils/prism_logger.dart';

/// Home 页状态控制器：
/// - 监听 SourceManager.activeRule 变化
/// - 统一加载：filters / pixiv prefs / pixiv cookie
/// - 统一分页与去重
/// - 统一错误状态（不直接依赖 BuildContext）
class HomeController extends ChangeNotifier {
  HomeController({
    required SourceManager sourceManager,
    required WallpaperService service,
    PrismLogger logger = const AppLogLogger(),
  })  : _sourceManager = sourceManager,
        _service = service,
        _logger = logger {
    _bindSourceManager(sourceManager);
    // 首次初始化
    _handleRuleMaybeChanged(force: true);
  }

  SourceManager _sourceManager;
  WallpaperService _service;
  final PrismLogger _logger;

  VoidCallback? _sourceListener;
  bool _disposed = false;

  // -------------------- public state --------------------

  List<UniWallpaper> get wallpapers => List.unmodifiable(_wallpapers);
  bool get loading => _loading;
  bool get hasMore => _hasMore;
  int get page => _page;
  bool get isScrolled => _isScrolled;
  Map<String, dynamic> get currentFilters => Map.unmodifiable(_currentFilters);
  String? get currentRuleId => _currentRuleId;
  String? get lastError => _lastError;

  // -------------------- internal state --------------------

  List<UniWallpaper> _wallpapers = <UniWallpaper>[];
  bool _loading = false;
  int _page = 1;
  bool _hasMore = true;
  bool _isScrolled = false;

  Map<String, dynamic> _currentFilters = <String, dynamic>{};
  String? _currentRuleId;

  String? _lastError;

  // 防止“异步回调晚到”覆盖新状态
  int _requestSeq = 0;

  // Pixiv keys
  static String _pixivCookiePrefsKey(String ruleId) => 'pixiv_cookie_$ruleId';
  static const String _kPixivPrefsKey = 'pixiv_preferences_v1';

  // -------------------- dependency update --------------------

  /// 用于 ProxyProvider 更新依赖
  void updateDeps({
    required SourceManager sourceManager,
    required WallpaperService service,
  }) {
    if (identical(_sourceManager, sourceManager) && identical(_service, service)) return;

    // 解绑旧 listener
    _unbindSourceManager();

    _sourceManager = sourceManager;
    _service = service;

    _bindSourceManager(sourceManager);

    // 依赖变化后，重新检查 rule
    _handleRuleMaybeChanged(force: true);
  }

  void _bindSourceManager(SourceManager sm) {
    _sourceListener = () {
      _handleRuleMaybeChanged();
    };
    sm.addListener(_sourceListener!);
  }

  void _unbindSourceManager() {
    final cb = _sourceListener;
    if (cb != null) {
      _sourceManager.removeListener(cb);
    }
    _sourceListener = null;
  }

  // -------------------- public actions --------------------

  /// UI 在滚动时调用：用于 AppBar 透明度与触底加载
  void onScroll({
    required double offset,
    required double maxScrollExtent,
  }) {
    final bool nextScrolled = offset > 0;
    if (nextScrolled != _isScrolled) {
      _isScrolled = nextScrolled;
      notifyListeners();
    }

    if (_loading || !_hasMore) return;
    if (offset >= maxScrollExtent - 200) {
      loadMore();
    }
  }

  Future<void> refresh() async {
    await _fetchData(refresh: true);
  }

  Future<void> loadMore() async {
    await _fetchData(refresh: false);
  }

  Future<void> applyFilters(Map<String, dynamic> newFilters) async {
    _currentFilters = Map<String, dynamic>.from(newFilters);
    await _saveFilters(newFilters);
    await refresh();
  }

  // -------------------- rule change pipeline --------------------

  Future<void> _handleRuleMaybeChanged({bool force = false}) async {
    final rule = _sourceManager.activeRule;
    final ruleId = rule?.id;

    if (!force && ruleId == _currentRuleId) return;

    _currentRuleId = ruleId;

    // rule 变更：重置核心状态（避免旧分页污染）
    _wallpapers = <UniWallpaper>[];
    _loading = false;
    _page = 1;
    _hasMore = true;
    _lastError = null;
    _currentFilters = <String, dynamic>{};

    notifyListeners();

    if (rule == null) return;

    // 串行初始化，避免 prefs/cookie 竞态
    await _loadFilters(rule);
    await _loadPixivPreferencesIfNeeded(rule);
    await _applyPixivCookieIfNeeded(rule);

    // 自动刷新
    await refresh();
  }

  // -------------------- persistence --------------------

  Future<void> _loadFilters(SourceRule rule) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('filter_prefs_${rule.id}');
      final Map<String, dynamic> next = <String, dynamic>{};

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final raw = jsonDecode(jsonStr);
        if (raw is Map) {
          raw.forEach((k, v) => next[k.toString()] = v);
        }
      }

      _currentFilters = next;
      notifyListeners();
    } catch (e) {
      _logger.debug('HomeController: loadFilters failed: $e');
    }
  }

  Future<void> _saveFilters(Map<String, dynamic> filters) async {
    final rule = _sourceManager.activeRule;
    if (rule == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (filters.isEmpty) {
        await prefs.remove('filter_prefs_${rule.id}');
      } else {
        await prefs.setString('filter_prefs_${rule.id}', jsonEncode(filters));
      }
    } catch (e) {
      _logger.debug('HomeController: saveFilters failed: $e');
    }
  }

  Future<void> _loadPixivPreferencesIfNeeded(SourceRule rule) async {
    if (!_service.isPixivRule(rule)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kPixivPrefsKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final m = jsonDecode(jsonStr);
      if (m is! Map) return;

      _service.setPixivPreferences(
        imageQuality: m['quality']?.toString(),
        showAi: m['show_ai'] == true,
        mutedTags: (m['muted_tags'] as List?)?.map((e) => e.toString()).toList(),
      );
    } catch (e) {
      _logger.debug('HomeController: loadPixivPreferences failed: $e');
    }
  }

  Future<void> _applyPixivCookieIfNeeded(SourceRule rule) async {
    if (!_service.isPixivRule(rule)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final fromPrefs = (prefs.getString(_pixivCookiePrefsKey(rule.id)) ?? '').trim();

      String fromHeaders = '';
      final h = rule.headers;
      if (h != null) {
        fromHeaders = ((h['Cookie'] ?? h['cookie'])?.toString() ?? '').trim();
      }

      final selected = fromPrefs.isNotEmpty ? fromPrefs : fromHeaders;
      _service.setPixivCookie(selected.isEmpty ? null : selected);

      _logger.debug(
        'HomeController: apply pixiv cookie rule=${rule.id} prefsLen=${fromPrefs.length} headersLen=${fromHeaders.length} selectedLen=${selected.length}',
      );

      // 若仅 headers 有 cookie，回填到 prefs 作为备份
      if (fromPrefs.isEmpty && fromHeaders.isNotEmpty) {
        await prefs.setString(_pixivCookiePrefsKey(rule.id), fromHeaders);
        _logger.debug('HomeController: backfilled pixiv cookie prefs from rule.headers');
      }
    } catch (e) {
      _logger.log('HomeController: apply pixiv cookie failed: $e');
    }
  }

  // -------------------- fetching --------------------

  Future<void> _fetchData({required bool refresh}) async {
    final rule = _sourceManager.activeRule;
    if (rule == null) return;
    if (_loading) return;

    final int seq = ++_requestSeq;

    _loading = true;
    _lastError = null;
    if (refresh) {
      _page = 1;
      _hasMore = true;
    }
    notifyListeners();

    try {
      final data = await _service.fetch(
        rule,
        page: _page,
        filterParams: _currentFilters,
      );

      if (_disposed) return;
      if (seq != _requestSeq) return; // 已有新请求，丢弃旧结果

      if (refresh) {
        _wallpapers = data;
        _hasMore = data.isNotEmpty;
      } else {
        final existingIds = _wallpapers.map((e) => e.id).toSet();
        final newItems = data.where((e) => existingIds.add(e.id)).toList();
        if (newItems.isEmpty) {
          _hasMore = false;
        } else {
          _wallpapers = <UniWallpaper>[..._wallpapers, ...newItems];
        }
      }

      if (data.isEmpty) _hasMore = false;
      if (_hasMore) _page++;

      _loading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      if (seq != _requestSeq) return;

      _loading = false;
      _lastError = '加载失败: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _unbindSourceManager();
    super.dispose();
  }
}