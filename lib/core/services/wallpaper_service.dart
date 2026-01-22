// lib/core/services/wallpaper_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine/rule_engine.dart';
import '../errors/error_mapper.dart';
import '../errors/prism_exception.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../network/image_header_policy.dart';
import '../pixiv/pixiv_repository.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';

/// UI 层唯一入口：
/// - 统一请求编排（Pixiv vs 通用 RuleEngine）
/// - 统一持久化（filters / pixiv prefs / cookie）
/// - 统一图片 Headers 策略（防 403）
/// - 统一错误映射（对 UI 输出友好文案）
class WallpaperService {
  final Dio _dio;
  final RuleEngine _engine;
  final PixivRepository _pixivRepo;
  final PreferencesStore _prefs;
  final PrismLogger _logger;
  final ErrorMapper _errorMapper;
  final ImageHeaderPolicy _imageHeaderPolicy;

  WallpaperService({
    required Dio dio,
    required RuleEngine engine,
    required PixivRepository pixivRepo,
    required PreferencesStore prefs,
    PrismLogger logger = const AppLogLogger(),
    ErrorMapper errorMapper = const ErrorMapper(),
    ImageHeaderPolicy imageHeaderPolicy = const ImageHeaderPolicy(),
  })  : _dio = dio,
        _engine = engine,
        _pixivRepo = pixivRepo,
        _prefs = prefs,
        _logger = logger,
        _errorMapper = errorMapper,
        _imageHeaderPolicy = imageHeaderPolicy;

  // -------------------- pixiv prefs / cookie --------------------

  bool isPixivRule(SourceRule? rule) => rule != null && _pixivRepo.supports(rule);

  PixivPreferences get pixivPreferences => _pixivRepo.prefs;
  PixivPagesConfig get pixivPagesConfig => _pixivRepo.pagesConfig;

  Future<void> hydratePixivContext(SourceRule rule) async {
    if (!isPixivRule(rule)) return;

    // 1) cookie: prefs 优先，其次 rule.headers
    String? cookie = await _prefs.loadPixivCookie(rule.id);

    final h = rule.headers;
    final fromHeaders = ((h?['Cookie'] ?? h?['cookie'])?.toString() ?? '').trim();
    if ((cookie ?? '').trim().isEmpty && fromHeaders.isNotEmpty) {
      cookie = fromHeaders;
      await _prefs.savePixivCookie(rule.id, cookie); // 回填备份
      _logger.debug('WallpaperService: backfilled pixiv cookie from rule.headers rule=${rule.id}');
    }

    _pixivRepo.setCookie((cookie ?? '').trim().isEmpty ? null : cookie);

    // 2) prefs
    final raw = await _prefs.loadPixivPrefsRaw();
    if (raw != null) {
      _pixivRepo.updatePreferences(
        _pixivRepo.prefs.copyWith(
          imageQuality: raw['quality']?.toString(),
          showAi: raw['show_ai'] == true,
          mutedTags: (raw['muted_tags'] as List?)?.map((e) => e.toString()).toList(),
        ),
      );
    }
  }

  Future<void> persistPixivPreferences() async {
    final p = _pixivRepo.prefs;
    await _prefs.savePixivPrefsRaw({
      'quality': p.imageQuality,
      'show_ai': p.showAi,
      'muted_tags': p.mutedTags,
    });
  }

  Future<void> setPixivCookieForRule(String ruleId, String? cookie) async {
    final c = (cookie ?? '').trim();
    await _prefs.savePixivCookie(ruleId, c.isEmpty ? null : c);
    _pixivRepo.setCookie(c.isEmpty ? null : c);
    _logger.log(c.isEmpty ? 'Pixiv cookie cleared' : 'Pixiv cookie updated');
  }

  // -------------------- filters persistence --------------------

  Future<Map<String, dynamic>> loadFilters(String ruleId) => _prefs.loadFilters(ruleId);

  Future<void> saveFilters(String ruleId, Map<String, dynamic> filters) =>
      _prefs.saveFilters(ruleId, filters);

  // -------------------- image headers --------------------

  Map<String, String>? imageHeadersFor({
    required UniWallpaper wallpaper,
    required SourceRule? rule,
  }) {
    return _imageHeaderPolicy.headersFor(wallpaper: wallpaper, rule: rule);
  }

  // -------------------- fetch --------------------

  Future<bool> getPixivLoginOk(SourceRule rule) async {
    if (!isPixivRule(rule)) return false;
    await hydratePixivContext(rule);
    try {
      return await _pixivRepo.getLoginOk(rule);
    } catch (e) {
      throw _errorMapper.map(e);
    }
  }

  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    try {
      if (isPixivRule(rule)) {
        await hydratePixivContext(rule);
        return await _pixivRepo.fetch(
          rule,
          page: page,
          query: query,
          filterParams: filterParams,
        );
      }

      return await _engine.fetch(
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

  // -------------------- download bytes --------------------

  Future<Uint8List> downloadImageBytes({
    required String url,
    Map<String, String>? headers,
  }) async {
    final u = url.trim();
    if (u.isEmpty) throw const PrismException(userMessage: '下载地址为空');

    try {
      final resp = await _dio.get<List<int>>(
        u,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) {
        throw const PrismException(userMessage: '下载失败：返回数据为空');
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      throw _errorMapper.map(e);
    }
  }
}
