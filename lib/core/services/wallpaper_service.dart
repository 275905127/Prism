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

  Future<UniWallpaper> fetchDetail({
    required UniWallpaper base,
    required SourceRule? rule,
  }) async {
    // ✅ Stage 2：按规则配置 detailUrl + candidates 进行详情补全
    // - Pixiv：此阶段先不做专用详情（避免污染边界/引入新接口）
    // - 通用规则：优先走 RuleEngine.fetchDetail(rule, base, headers: ...)
    if (rule == null) return base;

    try {
      final source = _sources.firstWhere(
        (s) => s.supports(rule),
        orElse: () => _sources.last,
      );

      // 详情补全也要先 restore（有些图源需要 cookie/header）
      await source.restoreSession(prefs: _prefs, rule: rule);

      // Pixiv 先不做 stage2（你之前明确说先不做 pixiv detail）
      if (isPixivRule(rule)) return base;

      // 给详情请求提供尽可能一致的 headers（含 rule.headers + policy）
      final headers = imageHeadersFor(wallpaper: base, rule: rule);

      // 不强依赖 BaseImageSource 扩展：动态探测 fetchDetail 方法
      final dynamic dyn = source;
      final dynamic result = await dyn.fetchDetail(rule, base, headers: headers);

      if (result is UniWallpaper) return result;
      return base;
    } catch (e) {
      // 详情补全失败不影响主流程：回退 base（DetailPage 仍能展示列表图）
      final mapped = _errorMapper.map(e);
      _logger.debug('WallpaperService.fetchDetail failed: ${mapped.debugMessage ?? mapped.userMessage}');
      return base;
    }
  }

  /// ✅ 统一构造“相似搜索 query”（Final）
///
/// 优先级（与 Wallhaven 官方一致）：
/// 1️⃣ Wallhaven 官方相似：like:<id>
/// 2️⃣ tags（最多 4 个，过滤 AI / r-）
/// 3️⃣ uploader（最后兜底）
///
/// 说明：
/// - like:<id> 仅在 Wallhaven API 下启用
/// - 不写入模型，不影响两阶段数据结构
String buildSimilarQuery(
  UniWallpaper w, {
  required SourceRule rule,
}) {
  // ------------------------------------------------------------
  // 1️⃣ Wallhaven 官方相似（严格限定）
  // ------------------------------------------------------------
  final isWallhaven =
      rule.id == 'wallhaven_ultimate_v3' &&
      rule.url.startsWith('https://wallhaven.cc/api/v1/');

  if (isWallhaven) {
    final wid = w.id.trim();

    // Wallhaven id 通常为 6~8 位字母数字，如：1q1mq3
    final looksLikeWallhavenId =
        RegExp(r'^[a-z0-9]{6,8}$', caseSensitive: false).hasMatch(wid);

    if (looksLikeWallhavenId) {
      return 'like:$wid';
    }
  }

  // ------------------------------------------------------------
  // 2️⃣ tags fallback（跨图源通用）
  // ------------------------------------------------------------
  final validTags = w.tags
      .map((t) => t.trim())
      .where((t) => t.length >= 2)
      .where((t) => !t.toLowerCase().startsWith('ai'))
      .where((t) => !t.toLowerCase().startsWith('r-'))
      .take(4)
      .toList(growable: false);

  if (validTags.isNotEmpty) {
    return validTags.join(' ');
  }

  // ------------------------------------------------------------
  // 3️⃣ uploader fallback（最后兜底）
  // ------------------------------------------------------------
  final uploader = w.uploader.trim();
  if (uploader.isNotEmpty && uploader.toLowerCase() != 'unknown user') {
    return 'user:$uploader';
  }

  return '';
}

  /// ✅ 统一“相似作品”入口（Pixiv 优先官方推荐；失败回退 query 搜索）
  ///
  /// - Pixiv 优先使用 Web Ajax 推荐接口（需要登录 + Referer）。
  ///   接口文档参考：
  ///   - /ajax/illust/{id}/recommend/init?limit=... 2
  ///   - /ajax/illust/recommend/illusts 3
  ///
  /// - 若无法拿到 Pixiv 的专用 Dio / cookie，或请求失败，则回退到 buildSimilarQuery + fetch()
  Future<List<UniWallpaper>> fetchSimilar({
    required UniWallpaper seed,
    required SourceRule rule,
    int page = 1,
    Map<String, dynamic>? filterParams,
  }) async {
    // 1) Pixiv：优先官方推荐（仅在确认为 Pixiv rule 时尝试）
    if (isPixivRule(rule) && hasPixivCookie) {
      final pixiv = await _tryFetchPixivRecommendSimilar(
        seed: seed,
        rule: rule,
        page: page,
      );
      if (pixiv != null) {
        // 去重：避免把自己也返回
        return pixiv.where((e) => e.id != seed.id).toList(growable: false);
      }
      // 失败继续走 fallback
    }

    // 2) Fallback：query 搜索
    final q = buildSimilarQuery(seed, rule: rule).trim();
    if (q.isEmpty) return const [];

    return fetch(
      rule,
      page: page,
      query: q,
      filterParams: filterParams,
    );
  }

  // -------------------- Pixiv Recommend (Private) --------------------

  static const int _pixivRecommendPageSize = 30;

  Future<List<UniWallpaper>?> _tryFetchPixivRecommendSimilar({
    required UniWallpaper seed,
    required SourceRule rule,
    required int page,
  }) async {
    // 只对纯数字作品 id 尝试推荐
    final seedId = int.tryParse(seed.id);
    if (seedId == null) return null;

    // 如果拿不到 pixiv 专用 Dio（带 cookie / 拦截器），直接放弃，走 fallback
    final Dio? pixivDio = _tryGetPixivDio();
    if (pixivDio == null) return null;

    try {
      // 推荐接口本身常见为 init + limit；分页能力不稳定。
      // 这里策略：
      // - page=1：走 recommend/init?limit=30
      // - page>1：尝试 recommend/illusts（若接口返回空则视为无更多）
      if (page <= 1) {
        final data = await _pixivAjaxGet(
          pixivDio,
          'https://www.pixiv.net/ajax/illust/$seedId/recommend/init',
          queryParameters: {'limit': _pixivRecommendPageSize},
          refererArtworkId: seedId,
        );
        final list = _extractPixivIllustList(data);
        if (list.isEmpty) return const <UniWallpaper>[];
        return list.map((e) => _mapPixivIllustToUni(e)).toList(growable: false);
      } else {
        // “推荐作品2”接口：需要 illust_ids[]，文档说明可用前一个接口结果作为基准 id 列表 4
        // 在不引入额外状态的前提下，这里用 seedId 作为基准数组做一次“尽力请求”。
        // 若 Pixiv 端不支持该用法，返回空即可，由 UI 表现为“没有更多了”。
        final offset = (page - 1) * _pixivRecommendPageSize;

        final data = await _pixivAjaxGet(
          pixivDio,
          'https://www.pixiv.net/ajax/illust/recommend/illusts',
          queryParameters: {
            'illust_ids[]': [seedId],
            'limit': _pixivRecommendPageSize,
            'offset': offset,
          },
          refererArtworkId: seedId,
        );

        final list = _extractPixivIllustList(data);
        if (list.isEmpty) return const <UniWallpaper>[];
        return list.map((e) => _mapPixivIllustToUni(e)).toList(growable: false);
      }
    } catch (e) {
      _logger.debug('Pixiv recommend failed, fallback to query: $e');
      return null;
    }
  }

  Dio? _tryGetPixivDio() {
    try {
      // 不改 PixivRepository 的前提下，用动态探测：
      // - repo.client.dio
      // - repo.dio
      final dynamic repo = _pixivRepo;

      try {
        final dynamic client = repo.client;
        final dynamic dio = client?.dio;
        if (dio is Dio) return dio;
      } catch (_) {}

      try {
        final dynamic dio = repo.dio;
        if (dio is Dio) return dio;
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _pixivAjaxGet(
    Dio dio,
    String url, {
    Map<String, dynamic>? queryParameters,
    required int refererArtworkId,
  }) async {
    final resp = await dio.get<dynamic>(
      url,
      queryParameters: queryParameters,
      options: Options(
        responseType: ResponseType.json,
        headers: {
          'Accept': 'application/json',
          'Referer': 'https://www.pixiv.net/artworks/$refererArtworkId',
        },
      ),
    );

    final data = resp.data;
    if (data is Map<String, dynamic>) return data;

    // Dio 也可能返回 Map<dynamic,dynamic>
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }

    throw const PrismException(userMessage: 'Pixiv 推荐接口返回异常');
  }

  List<Map<String, dynamic>> _extractPixivIllustList(Map<String, dynamic> data) {
    // 常见结构：{ error: false, body: { illusts: [...] } }
    final body = data['body'];
    if (body is Map) {
      final dynamic illusts = body['illusts'];
      if (illusts is List) {
        return illusts.map((e) => _asStringKeyMap(e)).whereType<Map<String, dynamic>>().toList(growable: false);
      }

      // 兼容可能的字段名
      final dynamic items = body['items'] ?? body['works'] ?? body['recommendations'];
      if (items is List) {
        return items.map((e) => _asStringKeyMap(e)).whereType<Map<String, dynamic>>().toList(growable: false);
      }
    }

    // 有些接口可能直接 body 为 list
    if (body is List) {
      return body.map((e) => _asStringKeyMap(e)).whereType<Map<String, dynamic>>().toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  UniWallpaper _mapPixivIllustToUni(Map<String, dynamic> illust) {
    final id = (illust['id'] ?? '').toString();
    final width = _toDouble(illust['width']);
    final height = _toDouble(illust['height']);

    // urls / url 兼容：thumbUrl 优先 small/regular，fullUrl 优先 original
    final urls = _asStringKeyMap(illust['urls']);
    final thumb = (urls?['small'] ??
            urls?['regular'] ??
            urls?['thumb'] ??
            illust['url'] ??
            illust['imageUrl'] ??
            '')
        .toString();

    final full = (urls?['original'] ??
            urls?['regular'] ??
            illust['url'] ??
            illust['imageUrl'] ??
            thumb)
        .toString();

    // tags：可能是 ["a","b"] 或 [{tag:"a"}]
    final tags = _parsePixivTags(illust['tags']);

    // uploader：可能在 userName / user_name / user.name
    final uploader = (illust['userName'] ??
            illust['user_name'] ??
            (_asStringKeyMap(illust['user'])?['name']) ??
            'Unknown User')
        .toString();

    // ugoira：常见 illustType==2
    final isUgoira = (illust['illustType']?.toString() == '2');

    // isAi：Pixiv 可能有 aiType / isAI 等字段，这里仅做兼容性判断
    final isAi = (illust['aiType']?.toString() == '2') ||
        (illust['isAI']?.toString().toLowerCase() == 'true');

    return UniWallpaper(
      id: id.isEmpty ? '0' : id,
      sourceId: 'pixiv',
      thumbUrl: thumb,
      fullUrl: full,
      width: width,
      height: height,
      isUgoira: isUgoira,
      isAi: isAi,
      tags: tags,
      uploader: uploader.isEmpty ? 'Unknown User' : uploader,
      // views/favs/fileSize/createdAt/mimeType：推荐接口一般不给，保持默认空串
    );
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  List<String> _parsePixivTags(dynamic raw) {
    if (raw is List) {
      final out = <String>[];
      for (final e in raw) {
        if (e is String) {
          final t = e.trim();
          if (t.isNotEmpty) out.add(t);
        } else if (e is Map) {
          final m = _asStringKeyMap(e);
          final t = (m?['tag'] ?? m?['name'] ?? '').toString().trim();
          if (t.isNotEmpty) out.add(t);
        }
      }
      return out;
    }
    return const <String>[];
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