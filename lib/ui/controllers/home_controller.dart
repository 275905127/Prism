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
    PrismLogger logger = const AppLogLogger(),
  })  : _sourceManager = sourceManager,
        _service = service,
        _logger = logger {
    _bindSourceManager(sourceManager);
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

  Future<void> loadMore() async => _fetchData(refresh: false);

  Future<void> applyFilters(Map<String, dynamic> newFilters) async {
    _currentFilters = Map<String, dynamic>.from(newFilters);
    final rule = _sourceManager.activeRule;
    if (rule != null) {
      await _service.saveFilters(rule.id, _currentFilters);
    }
    await refresh();
  }

  // -------------------- rule change pipeline --------------------

  Future<void> _handleRuleMaybeChanged({bool force = false}) async {
    final rule = _sourceManager.activeRule;
    final ruleId = rule?.id;

    if (!force && ruleId == _currentRuleId) return;

    _currentRuleId = ruleId;

    _wallpapers = <UniWallpaper>[];
    _loading = false;
    _page = 1;
    _hasMore = true;
    _lastError = null;
    _currentFilters = <String, dynamic>{};

    notifyListeners();

    if (rule == null) return;

    try {
      _currentFilters = await _service.loadFilters(rule.id);
      notifyListeners();

      // Pixiv: hydrate cookie + prefs once per rule switch
      await _service.hydratePixivContext(rule);
    } catch (e) {
      _logger.debug('HomeController: init for rule failed: $e');
    }

    await refresh();
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
      if (seq != _requestSeq) return;

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
