// lib/core/services/wallpaper_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../engine/rule_engine.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../pixiv/pixiv_repository.dart';
import '../utils/prism_logger.dart';

class WallpaperService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  late final Dio _pixivDio = _createPixivDioFrom(_dio);
  final PrismLogger _logger = const AppLogLogger();

  late final RuleEngine _standardEngine = RuleEngine(dio: _dio, logger: _logger);
  late final PixivRepository _pixivRepo = PixivRepository(dio: _pixivDio, logger: _logger);

  String? _pixivCookie;
  bool get hasPixivCookie => (_pixivCookie?.trim().isNotEmpty ?? false);

  void setPixivCookie(String? cookie) {
    final c = cookie?.trim() ?? '';
    _pixivCookie = c.isEmpty ? null : c;
    _pixivRepo.setCookie(_pixivCookie);
    _logger.log(_pixivCookie == null ? 'Pixiv cookie cleared (UI)' : 'Pixiv cookie set (UI)');
  }

  void setPixivPagesConfig({
    int? concurrency,
    Duration? timeoutPerItem,
    int? retryCount,
    Duration? retryDelay,
  }) {
    final current = _pixivRepo.pagesConfig;
    final next = current.copyWith(
      concurrency: concurrency,
      timeoutPerItem: timeoutPerItem,
      retryCount: retryCount,
      retryDelay: retryDelay,
    );
    _pixivRepo.updatePagesConfig(next);
  }

  // 设置 Pixiv 偏好 (画质/屏蔽)
  void setPixivPreferences({
    String? imageQuality,
    List<String>? mutedTags,
    bool? showAi,
  }) {
    final current = _pixivRepo.prefs;
    final next = current.copyWith(
      imageQuality: imageQuality,
      mutedTags: mutedTags,
      showAi: showAi,
    );
    _pixivRepo.updatePreferences(next);
  }

  PixivPreferences get pixivPreferences => _pixivRepo.prefs;
  PixivPagesConfig get pixivPagesConfig => _pixivRepo.pagesConfig;

  bool isPixivRule(SourceRule? rule) {
    if (rule == null) return false;
    return _pixivRepo.supports(rule);
  }

  Future<bool> getPixivLoginOk(SourceRule rule) async {
    if (!_pixivRepo.supports(rule)) return false;
    _syncPixivCookieFromRule(rule);
    return _pixivRepo.getLoginOk(rule);
  }

  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    if (_pixivRepo.supports(rule)) {
      _syncPixivCookieFromRule(rule);
      return _fetchFromPixiv(
        rule,
        page,
        query,
        filterParams: filterParams,
      );
    }
    return _standardEngine.fetch(
      rule,
      page: page,
      query: query,
      filterParams: filterParams,
    );
  }

  void _syncPixivCookieFromRule(SourceRule rule) {
    final headers = rule.headers;
    if (headers == null) {
      if (_pixivCookie != null) {
        _pixivRepo.setCookie(_pixivCookie);
      }
      return;
    }

    final cookie = (headers['Cookie'] ?? headers['cookie'])?.trim() ?? '';
    if (cookie.isNotEmpty) {
      _pixivRepo.setCookie(cookie);
      _logger.log('Pixiv cookie injected from rule');
      return;
    }

    if (_pixivCookie != null && _pixivCookie!.trim().isNotEmpty) {
      _pixivRepo.setCookie(_pixivCookie);
    } else {
      _pixivRepo.setCookie(null);
    }
  }

  Future<List<UniWallpaper>> _fetchFromPixiv(
    SourceRule rule,
    int page,
    String? query, {
    Map<String, dynamic>? filterParams,
  }) async {
    final String q = (query != null && query.trim().isNotEmpty)
        ? query
        : (rule.defaultKeyword ?? '').trim();

    return _pixivRepo.fetch(
      rule,
      page: page,
      query: q,
      filterParams: filterParams,
    );
  }

  Map<String, String>? getImageHeaders(SourceRule? rule) {
    if (rule == null) return null;

    if (_pixivRepo.supports(rule)) {
      _syncPixivCookieFromRule(rule);
      return _pixivRepo.buildImageHeaders();
    }
    return rule.buildRequestHeaders();
  }

  Future<Uint8List> downloadImageBytes({
    required String url,
    Map<String, String>? headers,
  }) async {
    final String u = url.trim();
    if (u.isEmpty) throw Exception('下载地址为空');

    final Map<String, String> finalHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ...?headers,
    };

    // 🔥 优化：下载逻辑健壮性增强
    // 自动检测是否为 Pixiv 图片域名 (i.pximg.net)，如果是且没传 Referer，自动补全。
    // 这样无论 UI 层是否漏传 header，下载都能成功，避免 403 Forbidden。
    if (u.contains('pximg.net') && !finalHeaders.containsKey('Referer')) {
      finalHeaders['Referer'] = 'https://www.pixiv.net/';
    }

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
    if (data is! List<int>) throw Exception('下载返回数据类型异常');

    final bytes = Uint8List.fromList(data);
    if (bytes.lengthInBytes < 100) throw Exception('文件过小，可能是错误页面');

    return bytes;
  }

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
