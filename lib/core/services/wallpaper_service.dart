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
///
/// 重要约束：
/// - hydratePixivContext 必须“永不抛异常”，否则会导致 HomeController.refresh 链路被打断，从而表现为“刷不出图”
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

  /// Pixiv 上下文注水：
  /// - 读取 cookie（prefs 优先，其次 rule.headers）
  /// - 读取 pixiv prefs
  ///
  /// 关键：此函数不能抛异常，也不能在“未读到 cookie”时清空 repo cookie
  Future<void> hydratePixivContext(SourceRule rule) async {
    if (!isPixivRule(rule)) return;

    // ---- 1) cookie ----
    String? cookieFromPrefs;
    try {
      cookieFromPrefs = await _prefs.loadPixivCookie(rule.id);
    } catch (e) {
      // prefs 内部可能有 !，这里必须兜底
      _logger.debug('WallpaperService: loadPixivCookie failed: $e');
      cookieFromPrefs = null;
    }

    final h = rule.headers;
    final cookieFromHeaders = ((h?['Cookie'] ?? h?['cookie'])?.toString() ?? '').trim();

    // 优先 prefs，其次 headers
    String resolved = (cookieFromPrefs ?? '').trim();
    if (resolved.isEmpty && cookieFromHeaders.isNotEmpty) {
      resolved = cookieFromHeaders;

      // 回填备份：失败也不能影响刷新/请求
      try {
        await _prefs.savePixivCookie(rule.id, resolved);
        _logger.debug('WallpaperService: backfilled pixiv cookie from rule.headers rule=${rule.id}');
      } catch (e) {
        _logger.debug('WallpaperService: backfill savePixivCookie failed: $e');
      }
    }

    // ✅ 关键：没有 cookie 时绝不主动清空 repo（避免登录态震荡）
    if (resolved.isNotEmpty) {
      _pixivRepo.setCookie(resolved);
    } else {
      _logger.debug('WallpaperService: pixiv cookie empty for rule=${rule.id} (keep repo state)');
    }

    // ---- 2) pixiv prefs ----
    Map<String, dynamic>? raw;
    try {
      raw = await _prefs.loadPixivPrefsRaw();
    } catch (e) {
      _logger.debug('WallpaperService: loadPixivPrefsRaw failed: $e');
      raw = null;
    }

    if (raw != null) {
      try {
        final mutedRaw = raw['muted_tags'];
        List<String>? muted;
        if (mutedRaw is List) {
          muted = mutedRaw.map((e) => e.toString()).toList();
        } else if (mutedRaw is String && mutedRaw.trim().isNotEmpty) {
          // 兼容旧格式：string -> split
          muted = mutedRaw.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        }

        _pixivRepo.updatePreferences(
          _pixivRepo.prefs.copyWith(
            imageQuality: raw['quality']?.toString(),
            showAi: raw['show_ai'] == true,
            mutedTags: muted,
          ),
        );
      } catch (e) {
        // prefs 格式异常也不能阻断请求
        _logger.debug('WallpaperService: apply pixiv prefs failed: $e');
      }
    }
  }

  Future<void> persistPixivPreferences() async {
    final p = _pixivRepo.prefs;
    try {
      await _prefs.savePixivPrefsRaw({
        'quality': p.imageQuality,
        'show_ai': p.showAi,
        'muted_tags': p.mutedTags,
      });
    } catch (e) {
      // 不能影响主流程
      _logger.debug('WallpaperService: savePixivPrefsRaw failed: $e');
    }
  }

  /// 保存 Pixiv Cookie（rule 粒度）
  /// - cookie 为空：清除 prefs；并清除 repo cookie
  /// - cookie 非空：保存 prefs；并注入 repo
  ///
  /// 注意：这里允许清空 repo，因为这是显式“保存/清空”的入口
  Future<void> setPixivCookieForRule(String ruleId, String? cookie) async {
    final c = (cookie ?? '').trim();

    try {
      await _prefs.savePixivCookie(ruleId, c.isEmpty ? null : c);
    } catch (e) {
      // prefs 失败也不应该让 UI 保存流程崩掉（否则会出现你看到的 save failed）
      _logger.debug('WallpaperService: savePixivCookie failed: $e');
    }

    // repo 注入不依赖 prefs
    _pixivRepo.setCookie(c.isEmpty ? null : c);

    _logger.log(c.isEmpty ? 'Pixiv cookie cleared' : 'Pixiv cookie updated');
  }

  // -------------------- filters persistence --------------------

  Future<Map<String, dynamic>> loadFilters(String ruleId) async {
    try {
      return await _prefs.loadFilters(ruleId);
    } catch (e) {
      _logger.debug('WallpaperService: loadFilters failed: $e');
      return <String, dynamic>{};
    }
  }

  Future<void> saveFilters(String ruleId, Map<String, dynamic> filters) async {
    try {
      await _prefs.saveFilters(ruleId, filters);
    } catch (e) {
      _logger.debug('WallpaperService: saveFilters failed: $e');
    }
  }

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

    // hydrate 不允许抛异常
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
        // hydrate 不允许阻断 pixiv fetch
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

  // -------------------- Compatibility APIs (keep UI compiling) --------------------

  /// Old UI expects a sync flag for login state display.
  bool get hasPixivCookie => _pixivRepo.hasCookie;

  /// Old UI calls this to persist pixiv preferences.
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

  /// Old UI calls this to obtain base headers (rule-level).
  /// Note: pximg Referer/UA 补齐需要 wallpaper URL，因此请优先使用 imageHeadersFor(...).
  Map<String, String>? getImageHeaders(SourceRule? rule) {
    final rh = rule?.headers;
    if (rh == null || rh.isEmpty) return null;

    final out = <String, String>{};
    rh.forEach((k, v) {
      if (v == null) return;
      out[k.toString()] = v.toString();
    });
    return out.isEmpty ? null : out;
  }
}