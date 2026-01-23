// lib/core/services/wallpaper_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine/base_image_source.dart'; // ✅ 引入接口
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
    // 使用通用接口寻找引擎
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
      // 1. 自动寻找匹配的引擎
      final source = _sources.firstWhere(
        (s) => s.supports(rule),
        orElse: () => _sources.last, // RuleEngine 是兜底
      );

      // 2. 恢复会话 (Hydrate)
      await source.restoreSession(prefs: _prefs, rule: rule);

      // 3. 执行请求
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

  /// 兼容旧代码：手动 Hydrate (通常由 fetch 自动调用，但如果 UI 需要提前调用也可保留)
  Future<void> hydratePixivContext(SourceRule rule) async {
    if (isPixivRule(rule)) {
      await _pixivRepo.restoreSession(prefs: _prefs, rule: rule);
    }
  }

  // ... (保留原有辅助方法) ...
  
  Future<void> persistPixivPreferences() async {
    try {
      final p = _pixivRepo.prefs;
      await _prefs.savePixivPrefsRaw({
        'quality': p.imageQuality, 'show_ai': p.showAi, 'muted_tags': p.mutedTags
      });
    } catch (_) {}
  }
  
  Future<void> setPixivCookieForRule(String ruleId, String? cookie) async {
    await _prefs.savePixivCookie(ruleId, cookie);
    _pixivRepo.setCookie(cookie);
  }
  
  Future<Map<String,dynamic>> loadFilters(String rid) async => await _prefs.loadFilters(rid);
  Future<void> saveFilters(String rid, Map<String,dynamic> f) async => await _prefs.saveFilters(rid, f);
  
  Map<String, String>? imageHeadersFor({required UniWallpaper wallpaper, required SourceRule? rule}) {
    return _imageHeaderPolicy.headersFor(wallpaper: wallpaper, rule: rule);
  }
  
  Map<String, String>? getImageHeaders(SourceRule? rule) {
      final rh = rule?.headers;
      if (rh == null) return null;
      return rh.map((k,v)=>MapEntry(k.toString(), v.toString()));
  }

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

  Future<Uint8List> downloadImageBytes({required String url, Map<String, String>? headers}) async {
      final u = url.trim();
      if (u.isEmpty) throw const PrismException(userMessage: '下载地址为空');
      try {
        final resp = await _dio.get<List<int>>(u, options: Options(responseType: ResponseType.bytes, headers: headers));
        if(resp.data == null || resp.data!.isEmpty) throw const PrismException(userMessage: '下载失败');
        return Uint8List.fromList(resp.data!);
      } catch (e) {
        throw _errorMapper.map(e);
      }
  }
}
