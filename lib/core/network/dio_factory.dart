// lib/core/network/dio_factory.dart
import 'package:dio/dio.dart';

import '../utils/prism_logger.dart';

class DioFactory {
  const DioFactory();

  Dio createBaseDio({required PrismLogger logger}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 25),
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
        headers: const {
          // A conservative UA; can be overridden per-rule.
          'User-Agent': 'Prism/1.0 (Flutter)',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          logger.debug('Dio => ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (resp, handler) {
          logger.debug('Dio <= ${resp.statusCode} ${resp.requestOptions.uri}');
          handler.next(resp);
        },
        onError: (e, handler) {
          logger.debug('Dio !! ${e.type} ${e.requestOptions.uri} ${e.message}');
          handler.next(e);
        },
      ),
    );

    return dio;
  }

  /// Pixiv requires different defaults (mainly headers) and can be adjusted
  /// further by [PixivRepository].
  Dio createPixivDioFrom(Dio base, {required PrismLogger logger}) {
    final dio = Dio(base.options.copyWith());
    dio.interceptors.addAll(base.interceptors);
    // Pixiv often needs a browser-like UA; repo may override per-request as well.
    dio.options.headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36';
    return dio;
  }
}
