// lib/core/services/wallpaper_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine/base_image_source.dart';
import '../engine/rule_engine.dart';
import '../errors/error_mapper.dart';
import '../errors/prism_exception.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../network/image_header_policy.dart';
import '../pixiv/pixiv_repository.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';

class WallpaperService {
  final Dio _dio;
  final PreferencesStore _prefs;
  final PrismLogger _logger;
  final ErrorMapper _errorMapper;
  final ImageHeaderPolicy _imageHeaderPolicy;
  final PixivRepository _pixivRepo; // 仍保留引用以供 settings 使用

  // ✅ 核心：图源引擎列表
  late final List<BaseImageSource> _sources;

  WallpaperService({
    required Dio dio,
    required RuleEngine engine,
    required PixivRepository pixivRepo,
    required PreferencesStore prefs,
    PrismLogger logger = const AppLogLogger(),
    ErrorMapper errorMapper = const ErrorMapper(),
    ImageHeaderPolicy imageHeaderPolicy = const ImageHeaderPolicy(),
  })  : _dio = dio,
        _pixivRepo = pixivRepo,
        _prefs = prefs,
        _logger = logger,
        _errorMapper = errorMapper,
        _imageHeaderPolicy = imageHeaderPolicy {
    // ✅ 初始化引擎列表，Pixiv 优先，通用引擎垫底
    _sources = [pixivRepo, engine];
  }

  // -------------------- Public APIs --------------------

  bool isPixivRule(SourceRule? rule) => rule != null && _pixivRepo.supports(rule);

  // 保持兼容旧 UI 的属性
  PixivPreferences get pixivPreferences => _pixivRepo.prefs;
  PixivPagesConfig get pixivPagesConfig => _pixivRepo.pagesConfig;
  bool get hasPixivCookie => _pixivRepo.hasCookie;

  Future<bool> getPixivLoginOk(SourceRule rule) async {
    final source = _sources.firstWhere((s) => s.supports(rule), orElse: () => _sources.last);
    await source.restoreSession(prefs: _prefs, rule: rule);
    return await source.checkLoginStatus(rule);
  }

  /// 统一 Fetch 入口
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    try {
      final source = _sources.firstWhere(
        (s) => s.supports(rule),
        orElse: () => _sources.last,
      );

      await source.restoreSession(prefs: _prefs, rule: rule);

      return await source.fetch(
        rule,
        page: page,
        query: query,
        filterParams: filterParams,
      );
    } catch (e) {
      final mapped = _errorMapper.map(e);
      _logger.debug('WallpaperService.fetch failed: ${mapped.debugMessage ?? mapped.userMessage}');
      throw mapped;
    }
  }

  /// 兼容旧代码：手动 Hydrate（通常由 fetch 自动调用）
  Future<void> hydratePixivContext(SourceRule rule) async {
    if (isPixivRule(rule)) {
      await _pixivRepo.restoreSession(prefs: _prefs, rule: rule);
    }
  }

  // -------------------- Detail & Similar (New) --------------------

  /// ✅ 两阶段详情补全入口（Service 统一收口，UI 不触 Repo/Engine）
  ///
  /// 当前阶段：Pixiv 的 fetch() 已尽量补齐 uploader/tags 等关键字段，
  /// 所以这里默认直接返回 base（不额外发请求，避免详情页再次放大网络成本）。
  ///
  /// 将来若你要做“进入详情页再补一次 detail/recommend”，
  /// 也可以在这里对 Pixiv 做专用分发（不需要污染 BaseImageSource）。
  Future<UniWallpaper> fetchDetail({
    required UniWallpaper base,
    required SourceRule? rule,
  }) async {
    if (rule == null) return base;

    final source = _sources.firstWhere(
      (s) => s.supports(rule),
      orElse: () => _sources.last,
    );

    try {
      final headers = imageHeadersFor(wallpaper: base, rule: rule);
      return await source.fetchDetail(
        rule,
        base,
        headers: headers,
      );
    } catch (e) {
      _logger.debug('WallpaperService.fetchDetail failed: $e');
      return base;
    }
  }

  /// ✅ 统一构造“相似搜索 query”
  ///
  /// 规则与当前 DetailPage 一致：
  /// - 优先 tags（过滤太短/AI/r- 前缀）取前 4 个
  /// - tags 为空则 fallback uploader -> user:<uploader>
  /// - 都没有则返回空串
  String buildSimilarQuery(UniWallpaper w) {
    final validTags = w.tags
        .map((t) => t.trim())
        .where((t) => t.length >= 2)
        .where((t) => !t.toLowerCase().startsWith('ai'))
        .where((t) => !t.toLowerCase().startsWith('r-'))
        .take(4)
        .toList(growable: false);

    if (validTags.isNotEmpty) return validTags.join(' ');

    final uploader = w.uploader.trim();
    if (uploader.isNotEmpty && uploader.toLowerCase() != 'unknown user') {
      return 'user:$uploader';
    }

    return '';
  }

  /// ✅ 统一“相似作品”入口：
  /// - Service 内拼 query
  /// - 复用 fetch() 走当前 active rule 的解析能力
  ///
  /// 说明：
  /// - 目前不引入 base_image_source 可选能力接口，所以这里以 query 搜索为主。
  /// - 未来若 PixivRepo 增加 recommend/related API，你也只需要改这里的 Pixiv 分支即可。
  Future<List<UniWallpaper>> fetchSimilar({
    required UniWallpaper seed,
    required SourceRule rule,
    int page = 1,
    Map<String, dynamic>? filterParams,
  }) async {
    final q = buildSimilarQuery(seed).trim();
    if (q.isEmpty) return const [];

    return fetch(
      rule,
      page: page,
      query: q,
      filterParams: filterParams,
    );
  }

  // -------------------- Preferences / Cookies / Filters --------------------

  Future<void> persistPixivPreferences() async {
    try {
      final p = _pixivRepo.prefs;
      await _prefs.savePixivPrefsRaw({
        'quality': p.imageQuality,
        'show_ai': p.showAi,
        'muted_tags': p.mutedTags,
      });
    } catch (_) {}
  }

  Future<void> setPixivCookieForRule(String ruleId, String? cookie) async {
    await _prefs.savePixivCookie(ruleId, cookie);
    _pixivRepo.setCookie(cookie);
  }

  Future<Map<String, dynamic>> loadFilters(String rid) async => await _prefs.loadFilters(rid);
  Future<void> saveFilters(String rid, Map<String, dynamic> f) async => await _prefs.saveFilters(rid, f);

  // -------------------- Headers --------------------

  Map<String, String>? imageHeadersFor({required UniWallpaper wallpaper, required SourceRule? rule}) {
    return _imageHeaderPolicy.headersFor(wallpaper: wallpaper, rule: rule);
  }

  Map<String, String>? getImageHeaders(SourceRule? rule) {
    final rh = rule?.headers;
    if (rh == null) return null;
    return rh.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  // -------------------- Pixiv settings helpers --------------------

  Future<void> setPixivPreferences({
    String? imageQuality,
    List<String>? mutedTags,
    bool? showAi,
  }) async {
    final current = _pixivRepo.prefs;
    final updated = current.copyWith(
      imageQuality: imageQuality,
      mutedTags: mutedTags,
      showAi: showAi,
    );
    _pixivRepo.updatePreferences(updated);
    await persistPixivPreferences();
  }

  // -------------------- Download --------------------

  Future<Uint8List> downloadImageBytes({required String url, Map<String, String>? headers}) async {
    final u = url.trim();
    if (u.isEmpty) throw const PrismException(userMessage: '下载地址为空');
    try {
      final resp = await _dio.get<List<int>>(
        u,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
        ),
      );
      if (resp.data == null || resp.data!.isEmpty) throw const PrismException(userMessage: '下载失败');
      return Uint8List.fromList(resp.data!);
    } catch (e) {
      throw _errorMapper.map(e);
    }
  }
}