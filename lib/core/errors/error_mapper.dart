// lib/core/errors/error_mapper.dart
import 'package:dio/dio.dart';

import 'prism_exception.dart';

class ErrorMapper {
  const ErrorMapper();

  PrismException map(Object error) {
    if (error is PrismException) return error;

    // RuleEngine uses ArgumentError('keyword_required') for "need query".
    if (error is ArgumentError && error.message == 'keyword_required') {
      return const PrismException(userMessage: '该图源需要关键词才能搜索。');
    }

    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        return PrismException(
          userMessage: '访问被拒绝（可能需要登录或请求头）。',
          debugMessage: 'Dio $status ${error.message}',
          cause: error,
        );
      }
      if (status != null && status >= 500) {
        return PrismException(
          userMessage: '服务器暂时不可用，请稍后重试。',
          debugMessage: 'Dio $status ${error.message}',
          cause: error,
        );
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return PrismException(
          userMessage: '网络超时，请检查网络后重试。',
          debugMessage: 'Dio timeout ${error.message}',
          cause: error,
        );
      }
      return PrismException(
        userMessage: '网络请求失败，请稍后重试。',
        debugMessage: 'Dio ${error.type} ${error.message}',
        cause: error,
      );
    }

    return PrismException(
      userMessage: '加载失败，请稍后重试。',
      debugMessage: error.toString(),
      cause: error,
    );
  }
}
