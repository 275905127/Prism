// lib/core/services/wallpaper_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine/rule_engine.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../pixiv/pixiv_repository.dart';
import '../utils/prism_logger.dart';

/// 桥梁层：统一管理所有图源引擎的调用
/// UI 只需与此类交互，无需关心底层是 RuleEngine 还是 PixivRepository
class WallpaperService {
  /// ✅ 通用网络出口（RuleEngine / 下载 等）
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  /// ✅ Pixiv 专用 Dio：必须有 Pixiv baseUrl，避免污染通用 Dio
  late final Dio _pixivDio = _createPixivDioFrom(_dio);

  /// ✅ 默认日志出口
  final PrismLogger _logger = const AppLogLogger();

  /// ✅ 通用引擎
  late final RuleEngine _standardEngine = RuleEngine(dio: _dio, logger: _logger);

  /// ✅ Pixiv 仓库
  late final PixivRepository _pixivRepo = PixivRepository(dio: _pixivDio, logger: _logger);

  /// ✅ Pixiv Cookie（来自 UI 持久化/内存注入）
  String? _pixivCookie;

  bool get hasPixivCookie => (_pixivCookie?.trim().isNotEmpty ?? false);

  /// ✅ UI 化入口：设置/清除 Pixiv Cookie（会立即影响 Ajax + i.pximg.net 图片）
  void setPixivCookie(String? cookie) {
    final c = cookie?.trim() ?? '';
    _pixivCookie = c.isEmpty ? null : c;
    _pixivRepo.setCookie(_pixivCookie);
    _logger.log(_pixivCookie == null ? 'Pixiv cookie cleared (UI)' : 'Pixiv cookie set (UI)');
  }

  bool isPixivRule(SourceRule? rule) {
    if (rule == null) return false;
    return _pixivRepo.supports(rule);
  }

  /// 核心方法：获取壁纸列表
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    // Pixiv 特殊源
    if (_pixivRepo.supports(rule)) {
      _syncPixivCookieFromRule(rule);
      return _fetchFromPixiv(
        rule,
        page,
        query,
        filterParams: filterParams,
      );
    }

    // 通用源
    return _standardEngine.fetch(
      rule,
      page: page,
      query: query,
      filterParams: filterParams,
    );
  }

  /// ✅ Pixiv：同步规则里的 Cookie → PixivClient
  /// 规则里的 Cookie 优先级更高（用于“规则自带 Cookie”场景）
  void _syncPixivCookieFromRule(SourceRule rule) {
    final headers = rule.headers;
    if (headers == null) {
      // 如果规则没有 headers，不动 UI 注入的 cookie
      if (_pixivCookie != null) {
        _pixivRepo.setCookie(_pixivCookie);
      }
      return;
    }

    final cookie = (headers['Cookie'] ?? headers['cookie'])?.trim() ?? '';
    if (cookie.isNotEmpty) {
      // 规则 Cookie 覆盖 UI Cookie
      _pixivRepo.setCookie(cookie);
      _logger.log('Pixiv cookie injected from rule');
      return;
    }

    // 规则没有 Cookie：回退 UI Cookie；若 UI 也没有，则清掉，避免残留
    if (_pixivCookie != null && _pixivCookie!.trim().isNotEmpty) {
      _pixivRepo.setCookie(_pixivCookie);
    } else {
      _pixivRepo.setCookie(null);
    }
  }

  /// Pixiv query 兜底
  Future<List<UniWallpaper>> _fetchFromPixiv(
    SourceRule rule,
    int page,
    String? query, {
    Map<String, dynamic>? filterParams,
  }) async {
    final String q = (query != null && query.trim().isNotEmpty)
        ? query
        : (rule.defaultKeyword ?? 'illustration').trim();

    return _pixivRepo.fetch(
      rule,
      page: page,
      query: q,
      filterParams: filterParams,
    );
  }

  /// UI 获取图片 Headers
  Map<String, String>? getImageHeaders(SourceRule? rule) {
    if (rule == null) return null;

    if (_pixivRepo.supports(rule)) {
      // ✅ 关键：即使还没 fetch，也先同步一次 Cookie，避免网格先渲染导致 403
      _syncPixivCookieFromRule(rule);
      return _pixivRepo.buildImageHeaders();
    }

    return rule.buildRequestHeaders();
  }

  /// 统一下载图片
  Future<Uint8List> downloadImageBytes({
    required String url,
    Map<String, String>? headers,
  }) async {
    final String u = url.trim();
    if (u.isEmpty) {
      throw Exception('下载地址为空');
    }

    final Map<String, String> finalHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ...?headers,
    };

    final resp = await _dio.get(
      u,
      options: Options(
        responseType: ResponseType.bytes,
        headers: finalHeaders,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    final sc = resp.statusCode ?? 0;
    if (sc >= 400) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: DioExceptionType.badResponse,
        error: 'HTTP $sc',
      );
    }

    final data = resp.data;
    if (data is! List<int>) {
      throw Exception('下载返回数据类型异常');
    }

    final bytes = Uint8List.fromList(data);
    if (bytes.lengthInBytes < 100) {
      throw Exception('文件过小，可能是错误页面');
    }

    return bytes;
  }

  /// 派生 Pixiv Dio
  static Dio _createPixivDioFrom(Dio base) {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://www.pixiv.net',
        connectTimeout: base.options.connectTimeout ?? const Duration(seconds: 15),
        sendTimeout: base.options.sendTimeout ?? const Duration(seconds: 20),
        receiveTimeout: base.options.receiveTimeout ?? const Duration(seconds: 25),
        responseType: ResponseType.json,
        validateStatus: base.options.validateStatus,
      ),
    );

    dio.httpClientAdapter = base.httpClientAdapter;
    dio.interceptors.clear();
    dio.interceptors.addAll(base.interceptors);

    return dio;
  }
}