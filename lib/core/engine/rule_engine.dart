import 'dart:math';
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';

import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../utils/app_log.dart';

class RuleEngine {
  final Dio _dio = Dio();

  // ---------- 基础工具 ----------

  dynamic _readDotPath(dynamic source, String path) {
    if (path.isEmpty) return null;
    if (path == '.') return source;

    dynamic cur = source;
    for (final part in path.split('.')) {
      if (cur == null) return null;

      if (cur is Map) {
        cur = cur[part];
        continue;
      }

      if (cur is List) {
        final idx = int.tryParse(part);
        if (idx == null || idx < 0 || idx >= cur.length) return null;
        cur = cur[idx];
        continue;
      }

      return null;
    }
    return cur;
  }

  T? _getValue<T>(String path, dynamic source) {
    try {
      if (path.isEmpty) return null;
      if (path == '.') return source as T;

      final p = path.trimLeft();
      if (p.startsWith(r'$')) {
        final jp = JsonPath(path);
        return jp.read(source).firstOrNull?.value as T?;
      }

      final v = _readDotPath(source, path);
      return v as T?;
    } catch (_) {
      return null;
    }
  }

  num _toNum(dynamic x) {
    if (x is num) return x;
    return num.tryParse(x?.toString() ?? '') ?? 0;
  }

  Map<String, String> _defaultUA() => const {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      };

  // ---------- App 内日志（打码） ----------

  String _mask(String v) {
    if (v.length <= 16) return '***';
    return '${v.substring(0, 12)}***';
  }

  Map<String, String> _maskHeaders(Map<String, String> headers) {
    final m = Map<String, String>.from(headers);
    if (m.containsKey('Authorization')) {
      m['Authorization'] = _mask(m['Authorization']!);
    }
    return m;
  }

  void _logReq(SourceRule rule, String url, Map<String, dynamic> params, Map<String, String> headers) {
    AppLog.I.add('REQ ${rule.id} GET $url');
    AppLog.I.add('    params=$params');
    AppLog.I.add('    headers=${_maskHeaders(headers)}');
  }

  void _logResp(SourceRule rule, int? status, String realUrl, dynamic data) {
    AppLog.I.add('RESP ${rule.id} status=${status ?? 'N/A'} url=$realUrl');
    final s = (data == null) ? '' : data.toString();
    AppLog.I.add('    body=${s.length > 400 ? s.substring(0, 400) + '...' : s}');
  }

  void _logErr(SourceRule rule, int? status, String realUrl, Object e, dynamic data) {
    AppLog.I.add('ERR ${rule.id} status=${status ?? 'N/A'} url=$realUrl');
    AppLog.I.add('    err=$e');
    final s = (data == null) ? '' : data.toString();
    if (s.isNotEmpty) {
      AppLog.I.add('    body=${s.length > 400 ? s.substring(0, 400) + '...' : s}');
    }
  }

  // ---------- 对外入口 ----------

  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final Map<String, dynamic> params = {};
    if (rule.fixedParams != null) params.addAll(rule.fixedParams!);

    final Map<String, String> reqHeaders = {
      ..._defaultUA(),
      ...?rule.headers,
    };

    // apiKey
    final apiKey = rule.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      final keyName =
          (rule.apiKeyName == null || rule.apiKeyName!.isEmpty) ? 'apikey' : rule.apiKeyName!;
      if (rule.apiKeyIn == 'header') {
        reqHeaders[keyName] = '${rule.apiKeyPrefix}$apiKey';
      } else {
        params[keyName] = apiKey;
      }
    }

    // merge 多选参数
    final Map<String, List<String>> mergeMulti = {};

    if (filterParams != null) {
      filterParams.forEach((key, value) {
        if (value is List) {
          SourceFilter? filterRule;
          if (rule.filters != null) {
            for (final f in rule.filters!) {
              if (f.key == key) {
                filterRule = f;
                break;
              }
            }
          }

          final encode = (filterRule?.encode ?? 'join').toLowerCase();

          if (encode == 'merge') {
            mergeMulti[key] = value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
          } else if (encode == 'repeat') {
            params[key] = value; // Dio 会变成重复 key
          } else {
            final separator = filterRule?.separator ?? ',';
            params[key] = value.join(separator);
          }
        } else {
          params[key] = value;
        }
      });
    }

    // ✅✅✅ 关键字策略（你缺的就是这一段）✅✅✅
    String? finalQuery = query;

    // 1) 用户没搜：用 defaultKeyword
    if ((finalQuery == null || finalQuery.trim().isEmpty) &&
        rule.defaultKeyword != null &&
        rule.defaultKeyword!.trim().isNotEmpty) {
      finalQuery = rule.defaultKeyword;
    }

    // 2) keywordRequired = true 但最终还是没有关键词：直接报错，不发请求
    if (rule.keywordRequired && (finalQuery == null || finalQuery.trim().isEmpty)) {
      throw Exception("该图源需要关键词：query 为空（请先搜索或在规则里设置 default_keyword）");
    }

    // 3) 有关键词：注入到 params
    if (finalQuery != null && finalQuery.trim().isNotEmpty) {
      params[rule.paramKeyword] = finalQuery.trim();
    }
    // ✅✅✅ 关键字策略结束 ✅✅✅

    try {
      if (rule.responseType == 'random') {
        return await _fetchRandomMode(rule, params, reqHeaders);
      } else {
        if (rule.paramPage.isNotEmpty) {
          params[rule.paramPage] = page;
        }

        if (mergeMulti.isEmpty) {
          return await _fetchJsonMode(rule, params, reqHeaders);
        }
        return await _fetchJsonModeMerge(rule, params, reqHeaders, mergeMulti);
      }
    } catch (e) {
      AppLog.I.add('Engine Error: $e');
      rethrow;
    }
  }

  // ---------- random 模式（原样，只加日志） ----------

  Future<List<UniWallpaper>> _fetchRandomMode(
    SourceRule rule,
    Map<String, dynamic> params,
    Map<String, String> headers,
  ) async {
    const int batchSize = 6;
    const int delayMs = 300;

    _logReq(rule, rule.url, params, headers);

    final futures = List.generate(batchSize, (index) async {
      await Future.delayed(Duration(milliseconds: index * delayMs));

      try {
        final requestParams = Map<String, dynamic>.from(params);
        requestParams['_t'] = DateTime.now().millisecondsSinceEpoch + index;
        requestParams['_r'] = Random().nextInt(10000);

        String? finalUrl;

        try {
          final response = await _dio.head(
            rule.url,
            queryParameters: requestParams,
            options: Options(
              headers: headers,
              followRedirects: true,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (status) => status != null && status < 400,
            ),
          );
          finalUrl = response.realUri.toString();
        } catch (e) {
          try {
            final response = await _dio.get(
              rule.url,
              queryParameters: requestParams,
              options: Options(
                headers: headers,
                followRedirects: true,
                responseType: ResponseType.stream,
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                validateStatus: (s) => s != null && s < 500,
              ),
            );
            finalUrl = response.realUri.toString();
            (response.data as ResponseBody).close();
          } catch (_) {
            return null;
          }
        }

        if (finalUrl == null) return null;

        final uri = Uri.parse(finalUrl);
        if (uri.queryParameters.containsKey('_t') || uri.queryParameters.containsKey('_r')) {
          final newQueryParams = Map<String, String>.from(uri.queryParameters);
          newQueryParams.remove('_t');
          newQueryParams.remove('_r');
          finalUrl = uri.replace(queryParameters: newQueryParams).toString();
        }

        return finalUrl;
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(futures);

    final List<UniWallpaper> wallpapers = [];
    for (var url in results) {
      if (url != null && url.startsWith('http')) {
        if (!wallpapers.any((w) => w.fullUrl == url)) {
          wallpapers.add(UniWallpaper(
            id: url.hashCode.toString(),
            sourceId: rule.id,
            thumbUrl: url,
            fullUrl: url,
            width: 0,
            height: 0,
          ));
        }
      }
    }

    AppLog.I.add('RESP ${rule.id} random_count=${wallpapers.length}');
    return wallpapers;
  }

  // ---------- json 解析（原样） ----------

  List<UniWallpaper> _parseJsonToWallpapers(SourceRule rule, dynamic jsonMap) {
    final listPath = JsonPath(rule.listPath);
    final match = listPath.read(jsonMap).firstOrNull;

    if (match == null || match.value is! List) return [];

    final List list = match.value as List;

    return list.map((item) {
      final id = _getValue<String>(rule.idPath, item) ?? DateTime.now().toString();

      String thumb = _getValue<String>(rule.thumbPath, item) ?? "";
      String full = _getValue<String>(rule.fullPath, item) ?? thumb;

      if (rule.imagePrefix != null && rule.imagePrefix!.isNotEmpty) {
        if (!thumb.startsWith('http')) thumb = rule.imagePrefix! + thumb;
        if (!full.startsWith('http')) full = rule.imagePrefix! + full;
      }

      final width = _toNum(_getValue(rule.widthPath ?? '', item)).toDouble();
      final height = _toNum(_getValue(rule.heightPath ?? '', item)).toDouble();
      final grade = _getValue<String>(rule.gradePath ?? '', item);

      return UniWallpaper(
        id: id.toString(),
        sourceId: rule.id,
        thumbUrl: thumb,
        fullUrl: full,
        width: width,
        height: height,
        grade: grade,
      );
    }).toList();
  }

  // ---------- json 单次请求（加日志 + 4xx body） ----------

  Future<List<UniWallpaper>> _fetchJsonMode(
    SourceRule rule,
    Map<String, dynamic> params,
    Map<String, String> headers,
  ) async {
    _logReq(rule, rule.url, params, headers);

    try {
      final response = await _dio.get(
        rule.url,
        queryParameters: params,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      _logResp(rule, response.statusCode, response.realUri.toString(), response.data);

      final sc = response.statusCode ?? 0;
      if (sc >= 400) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'HTTP $sc',
        );
      }

      return _parseJsonToWallpapers(rule, response.data);
    } on DioException catch (e) {
      _logErr(rule, e.response?.statusCode, e.requestOptions.uri.toString(), e, e.response?.data);
      rethrow;
    } catch (e) {
      _logErr(rule, null, rule.url, e, null);
      rethrow;
    }
  }

  // ---------- json merge 多请求（加日志 + 4xx body） ----------

  Future<List<UniWallpaper>> _fetchJsonModeMerge(
    SourceRule rule,
    Map<String, dynamic> baseParams,
    Map<String, String> headers,
    Map<String, List<String>> mergeMulti,
  ) async {
    List<Map<String, dynamic>> paramSets = [Map<String, dynamic>.from(baseParams)];

    mergeMulti.forEach((key, values) {
      final List<Map<String, dynamic>> next = [];
      for (final ps in paramSets) {
        for (final v in values) {
          final m = Map<String, dynamic>.from(ps);
          m[key] = v;
          next.add(m);
        }
      }
      paramSets = next;
    });

    AppLog.I.add('MERGE ${rule.id} requests=${paramSets.length} keys=${mergeMulti.keys.toList()}');

    final List<UniWallpaper> merged = [];
    final Set<String> seen = {};

    for (final ps in paramSets) {
      _logReq(rule, rule.url, ps, headers);

      try {
        final resp = await _dio.get(
          rule.url,
          queryParameters: ps,
          options: Options(
            headers: headers,
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        _logResp(rule, resp.statusCode, resp.realUri.toString(), resp.data);

        final sc = resp.statusCode ?? 0;
        if (sc >= 400) {
          throw DioException(
            requestOptions: resp.requestOptions,
            response: resp,
            type: DioExceptionType.badResponse,
            error: 'HTTP $sc',
          );
        }

        final items = _parseJsonToWallpapers(rule, resp.data);
        for (final it in items) {
          if (seen.add(it.id)) merged.add(it);
        }
      } on DioException catch (e) {
        _logErr(rule, e.response?.statusCode, e.requestOptions.uri.toString(), e, e.response?.data);
        rethrow;
      } catch (e) {
        _logErr(rule, null, rule.url, e, null);
        rethrow;
      }
    }

    AppLog.I.add('MERGE ${rule.id} merged=${merged.length}');
    return merged;
  }
}