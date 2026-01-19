// lib/core/engine/rule_engine.dart
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class RuleEngine {
  final Dio _dio = Dio();

  /// 支持点路径：a.b.c / a.0.b
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

  /// 统一取值：
  /// - '.' 返回整个对象
  /// - '$...' 走 JSONPath
  /// - 其他走点路径
  T? _getValue<T>(String path, dynamic source) {
    try {
      if (path.isEmpty) return null;
      if (path == '.') return source as T;

      final p = path.trimLeft();

      // 只在以 $ 开头时使用 JSONPath（更明确，避免误判）
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

  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final Map<String, dynamic> params = {};
    if (rule.fixedParams != null) params.addAll(rule.fixedParams!);

    // ⚠️ 仍然保持你现有行为：把 apiKey 塞到 apikey
    // 后面你要做成通用的（query/header/name可配置）再改
    if (rule.apiKey != null && rule.apiKey!.isNotEmpty) {
      params['apikey'] = rule.apiKey;
    }

    if (filterParams != null) {
      filterParams.forEach((key, value) {
        if (value is List) {
          // 找不到 filter 也会降级用 ',' 拼
          final filterRule = rule.filters?.firstWhere(
            (f) => f.key == key,
            orElse: () => SourceFilter(key: '', name: '', type: '', options: []),
          );
          final separator = filterRule.separator;
          params[key] = value.join(separator);
        } else {
          params[key] = value;
        }
      });
    }

    if (query != null && query.isNotEmpty) {
      params[rule.paramKeyword] = query;
    }

    try {
      if (rule.responseType == 'random') {
        return await _fetchRandomMode(rule, params);
      } else {
        params[rule.paramPage] = page;
        return await _fetchJsonMode(rule, params);
      }
    } catch (e) {
      // ignore: avoid_print
      print("Engine Error: $e");
      rethrow;
    }
  }

  // 🔥 核心逻辑：直链嗅探与锁定
  Future<List<UniWallpaper>> _fetchRandomMode(
    SourceRule rule,
    Map<String, dynamic> params,
  ) async {
    const int batchSize = 6;
    const int delayMs = 300;

    final futures = List.generate(batchSize, (index) async {
      await Future.delayed(Duration(milliseconds: index * delayMs));

      try {
        final requestParams = Map<String, dynamic>.from(params);
        requestParams['_t'] = DateTime.now().millisecondsSinceEpoch + index;
        requestParams['_r'] = Random().nextInt(10000);

        String? finalUrl;

        // 1) HEAD 优先
        try {
          final response = await _dio.head(
            rule.url,
            queryParameters: requestParams,
            options: Options(
              headers: rule.headers,
              followRedirects: true,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (status) => status != null && status < 400,
            ),
          );
          finalUrl = response.realUri.toString();
        } catch (e) {
          // 2) HEAD 不行回退 GET(stream)
          // ignore: avoid_print
          print("HEAD failed, retrying with GET: $e");
          try {
            final response = await _dio.get(
              rule.url,
              queryParameters: requestParams,
              options: Options(
                headers: rule.headers,
                followRedirects: true,
                responseType: ResponseType.stream,
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );
            finalUrl = response.realUri.toString();
            (response.data as ResponseBody).close();
          } catch (_) {
            return null;
          }
        }

        if (finalUrl == null) return null;

        // 3) 参数净化：去掉 _t/_r
        final uri = Uri.parse(finalUrl);
        if (uri.queryParameters.containsKey('_t') ||
            uri.queryParameters.containsKey('_r')) {
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
    return wallpapers;
  }

  Future<List<UniWallpaper>> _fetchJsonMode(
    SourceRule rule,
    Map<String, dynamic> params,
  ) async {
    final response = await _dio.get(
      rule.url,
      queryParameters: params,
      options: Options(
        headers: rule.headers ??
            {
              "User-Agent":
                  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    final jsonMap = response.data;

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
}