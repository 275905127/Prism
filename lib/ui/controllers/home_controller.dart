// lib/ui/controllers/home_controller.dart
import 'package:flutter/foundation.dart';

import '../../core/errors/prism_exception.dart';
import '../../core/manager/source_manager.dart';
import '../../core/models/source_rule.dart';
import '../../core/models/uni_wallpaper.dart';
import '../../core/services/wallpaper_service.dart';
import '../../core/utils/prism_logger.dart';

/// Home 页状态控制器：
/// - 监听 SourceManager.activeRule 变化
/// - 统一加载：filters / pixiv prefs / pixiv cookie（通过 WallpaperService 持久化）
/// - 统一分页与去重
/// - 统一错误状态（不直接依赖 BuildContext）
class HomeController extends ChangeNotifier {
  HomeController({
    required SourceManager sourceManager,
    required WallpaperService service,
    required PrismLogger logger,
  })  : _sourceManager = sourceManager,
        _service = service,
        _logger = logger {
    _bindSourceManager(sourceManager);
    // 启动时强制跑一次规则同步
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

  // 防止 loadMore 并发
  bool _pagingInFlight = false;

  // -------------------- dependency update --------------------

  void updateDeps({
    required SourceManager sourceManager,
    required WallpaperService service,
  }) {
    if (identical(_sourceManager, sourceManager) && identical(_service, service)) return;

    _unbindSourceManager();

    _sourceManager = sourceManager;
    _service = service;

    _bindSourceManager(sourceManager);

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

  Future<void> refresh() async => _fetchData(refresh: true);

  Future<void> loadMore() async {
    // 避免并发分页
    if (_pagingInFlight) return;
    _pagingInFlight = true;
    try {
      await _fetchData(refresh: false);
    } finally {
      _pagingInFlight = false;
    }
  }

  Future<void> applyFilters(Map<String, dynamic> newFilters) async {
    _currentFilters = Map<String, dynamic>.from(newFilters);
    final rule = _sourceManager.activeRule;
    if (rule != null) {
      try {
        await _service.saveFilters(rule.id, _currentFilters);
      } catch (e) {
        _logger.debug('HomeController: saveFilters failed: $e');
      }
    }
    await refresh();
  }

  // -------------------- rule change pipeline --------------------

  Future<void> _handleRuleMaybeChanged({bool force = false}) async {
    final rule = _sourceManager.activeRule;
    final ruleId = rule?.id;

    if (!force && ruleId == _currentRuleId) return;

    _currentRuleId = ruleId;

    // 重置页面状态
    _wallpapers = <UniWallpaper>[];
    _loading = false;
    _page = 1;
    _hasMore = true;
    _lastError = null;
    _currentFilters = <String, dynamic>{};

    notifyListeners();

    if (rule == null) return;

    final localRuleId = rule.id;

    // 规则切换时：先加载 filters，再尽力 hydrate pixiv 上下文（不阻断 refresh）
    try {
      _currentFilters = await _service.loadFilters(localRuleId);
      if (_disposed) return;
      if (_currentRuleId != localRuleId) return;
      notifyListeners();
    } catch (e) {
      _logger.debug('HomeController: loadFilters failed: $e');
    }

    try {
      await _service.hydratePixivContext(rule);
    } catch (e) {
      // 这里不让异常中断刷新，否则就会表现为“刷不出图”
      _logger.debug('HomeController: hydratePixivContext failed: $e');
    }

    // 不管 hydrate 成功与否都刷新
    await refresh();
  }

  // -------------------- fetching --------------------

  Future<void> _fetchData({required bool refresh}) async {
    final rule = _sourceManager.activeRule;
    if (rule == null) return;
    if (_loading) return;

    final String localRuleId = rule.id;
    final int seq = ++_requestSeq;

    _loading = true;
    _lastError = null;

    if (refresh) {
      _page = 1;
      _hasMore = true;
    }

    notifyListeners();

    try {
      final int pageToFetch = _page;

      final data = await _service.fetch(
        rule,
        page: pageToFetch,
        filterParams: _currentFilters,
      );

      if (_disposed) return;
      // 请求过期：seq 变化或 rule 变化都忽略
      if (seq != _requestSeq) return;
      if (_currentRuleId != localRuleId) return;

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
      if (_hasMore) _page = pageToFetch + 1;

      _loading = false;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      if (seq != _requestSeq) return;
      if (_currentRuleId != localRuleId) return;

      _loading = false;

      // 真实异常写日志，UI 只拿友好提示
      _logger.debug('HomeController: fetch failed: $e');

      final msg = (e is PrismException) ? e.userMessage : '加载失败，请稍后重试。';
      _lastError = msg;
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