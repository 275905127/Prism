import 'dart:math';
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class RuleEngine {
  final Dio _dio = Dio();

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

    // apiKey 逻辑（按你现有的写法/字段）
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

    // ✅ 收集需要 “merge 多请求” 的多选参数
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
            // ✅ 多请求合并
            mergeMulti[key] = value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
          } else if (encode == 'repeat') {
            // ✅ repeat：q=red&q=blue 这种（部分 API 支持）
            // Dio 对 list 的 queryParameters 会变成重复 key
            params[key] = value;
          } else {
            // ✅ join：red,blue
            final separator = filterRule?.separator ?? ',';
            params[key] = value.join(separator);
          }
        } else {
          params[key] = value;
        }
      });
    }

    if (query != null && query.trim().isNotEmpty) {
      params[rule.paramKeyword] = query.trim();
    }

    try {
      if (rule.responseType == 'random') {
        return await _fetchRandomMode(rule, params, reqHeaders);
      } else {
        if (rule.paramPage.isNotEmpty) {
          params[rule.paramPage] = page;
        }

        // ✅ 如果没有 merge 多选 -> 正常单次请求
        if (mergeMulti.isEmpty) {
          return await _fetchJsonMode(rule, params, reqHeaders);
        }

        // ✅ 有 merge 多选 -> 多次请求合并去重
        return await _fetchJsonModeMerge(rule, params, reqHeaders, mergeMulti);
      }
    } catch (e) {
      // ignore: avoid_print
      print("Engine Error: $e");
      rethrow;
    }
  }

  // ---------------- random 模式：保持你原来的 ----------------

  Future<List<UniWallpaper>> _fetchRandomMode(
    SourceRule rule,
    Map<String, dynamic> params,
    Map<String, String> headers,
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
          // ignore: avoid_print
          print("HEAD failed, retrying with GET: $e");
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
    return wallpapers;
  }

  // ---------------- json 模式：解析拆出来复用 ----------------

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

  Future<List<UniWallpaper>> _fetchJsonMode(
    SourceRule rule,
    Map<String, dynamic> params,
    Map<String, String> headers,
  ) async {
    final response = await _dio.get(
      rule.url,
      queryParameters: params,
      options: Options(
        headers: headers,
        responseType: ResponseType.json,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    return _parseJsonToWallpapers(rule, response.data);
  }

  // ✅ merge：展开参数组合 -> 多次请求 -> 合并去重
  Future<List<UniWallpaper>> _fetchJsonModeMerge(
    SourceRule rule,
    Map<String, dynamic> baseParams,
    Map<String, String> headers,
    Map<String, List<String>> mergeMulti,
  ) async {
    // 生成一组 paramSet（支持多个 merge 维度）
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

    final List<UniWallpaper> merged = [];
    final Set<String> seen = {};

    // 为了不把你直接送到 429：默认串行请求（稳）
    for (final ps in paramSets) {
      final resp = await _dio.get(
        rule.url,
        queryParameters: ps,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final items = _parseJsonToWallpapers(rule, resp.data);
      for (final it in items) {
        if (seen.add(it.id)) merged.add(it);
      }
    }

    return merged;
  }
}