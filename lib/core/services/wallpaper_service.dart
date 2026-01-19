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

  /// ✅ 默认日志出口：写入 AppLog（日志页继续可用）
  final PrismLogger _logger = const AppLogLogger();

  /// ✅ 通用引擎复用同一个 Dio（避免 RuleEngine 私有 Dio 绕开全局策略）
  late final RuleEngine _standardEngine = RuleEngine(dio: _dio, logger: _logger);

  /// ✅ Pixiv 仓库复用 Pixiv 专用 Dio（但共享通用 Dio 的拦截器/adapter 策略）
  late final PixivRepository _pixivRepo = PixivRepository(dio: _pixivDio, logger: _logger);

  /// 核心方法：获取壁纸列表
  /// 内部自动判断使用哪个引擎
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    // 1. 路由逻辑：判断是否为 Pixiv 特殊源
    if (_pixivRepo.supports(rule)) {
      return _fetchFromPixiv(rule, page, query);
    }

    // 2. 默认逻辑：走通用 JSON 引擎
    return _standardEngine.fetch(
      rule,
      page: page,
      query: query,
      filterParams: filterParams,
    );
  }

  /// 辅助逻辑：Pixiv 需要特殊处理 query
  Future<List<UniWallpaper>> _fetchFromPixiv(
    SourceRule rule,
    int page,
    String? query,
  ) async {
    // Pixiv 首页必须有关键词：优先用规则 defaultKeyword，否则兜底
    final String q = (query != null && query.trim().isNotEmpty)
        ? query
        : (rule.defaultKeyword ?? 'illustration').trim();

    return _pixivRepo.fetch(
      rule,
      page: page,
      query: q,
    );
  }

  /// UI 获取图片时需要的 Headers (用于 CachedNetworkImage / Dio)
  /// 统一在这里处理，UI 不必写 if-else
  Map<String, String>? getImageHeaders(SourceRule? rule) {
    if (rule == null) return null;

    if (_pixivRepo.supports(rule)) {
      return _pixivRepo.buildImageHeaders();
    }

    return rule.buildRequestHeaders();
  }

  /// ✅ UI 禁止直接 Dio：下载图片 bytes 统一收口到 Service
  /// - 自动注入保底 UA
  /// - 复用 headers（Authorization/Client-ID/Referer/Cookie 等）
  /// - 统一超时与错误抛出
  Future<Uint8List> downloadImageBytes({
    required String url,
    Map<String, String>? headers,
  }) async {
    final String u = url.trim();
    if (u.isEmpty) {
      throw Exception('下载地址为空');
    }

    final Map<String, String> finalHeaders = <String, String>{
      // 保底 UA
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      ...?headers,
    };

    try {
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
    } on DioException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  /// ✅ 从通用 Dio 派生 Pixiv Dio：
  /// - 共享 adapter（代理/证书/自定义 transport）
  /// - 共享 interceptors（统一日志/重试/UA/鉴权注入等）
  /// - 单独设置 Pixiv 的 baseUrl 与超时
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

    // 共享 transport（非常关键：代理/抓包/证书策略通常在这里）
    dio.httpClientAdapter = base.httpClientAdapter;

    // 共享拦截器（复用同一实例，保证策略一致）
    dio.interceptors.clear();
    dio.interceptors.addAll(base.interceptors);

    return dio;
  }
}