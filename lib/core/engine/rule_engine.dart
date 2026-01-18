// lib/core/engine/rule_engine.dart
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class RuleEngine {
  final Dio _dio = Dio();

  Future<List<UniWallpaper>> fetch(SourceRule rule, {
    int page = 1, 
    String? query,
    Map<String, dynamic>? filterParams, 
  }) async {
    final Map<String, dynamic> params = {};
    if (rule.fixedParams != null) params.addAll(rule.fixedParams!);
    if (rule.apiKey != null && rule.apiKey!.isNotEmpty) params['apikey'] = rule.apiKey;
    
    if (filterParams != null) {
      filterParams.forEach((key, value) {
        if (value is List) {
          final filterRule = rule.filters?.firstWhere((f) => f.key == key, orElse: () => SourceFilter(key: '', name: '', type: '', options: []));
          final separator = filterRule?.separator ?? ',';
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
      print("Engine Error: $e");
      rethrow;
    }
  }

  // 🔥 核心逻辑：直链嗅探与锁定
  Future<List<UniWallpaper>> _fetchRandomMode(SourceRule rule, Map<String, dynamic> params) async {
    const int batchSize = 6; 
    const int delayMs = 300; 

    final futures = List.generate(batchSize, (index) async {
      await Future.delayed(Duration(milliseconds: index * delayMs));

      try {
        // 构造防缓存参数
        final requestParams = Map<String, dynamic>.from(params);
        requestParams['_t'] = DateTime.now().millisecondsSinceEpoch + index;
        requestParams['_r'] = Random().nextInt(10000); 

        String? finalUrl;
        
        // 1. 优先尝试 HEAD 请求 (省流量，速度快)
        try {
          final response = await _dio.head(
            rule.url,
            queryParameters: requestParams,
            options: Options(
              headers: rule.headers,
              followRedirects: true, // 关键：自动跟随重定向
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (status) => status != null && status < 400,
            ),
          );
          finalUrl = response.realUri.toString();
        } catch (e) {
          // 2. 如果 HEAD 失败 (有些服务器禁止 HEAD)，回退尝试 GET
          // 这里的 trick 是：我们并不需要 body，只要 header 里的 URL
          // 但 Dio 的 GET 会下载 body，所以这只是个保底方案
          // 对于大文件这可能会浪费一点流量，但在 API 兼容性上更好
          print("HEAD failed, retrying with GET: $e");
          try {
             final response = await _dio.get(
              rule.url,
              queryParameters: requestParams,
              options: Options(
                headers: rule.headers,
                followRedirects: true,
                responseType: ResponseType.stream, // 关键：用流模式，不下载具体内容
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );
            finalUrl = response.realUri.toString();
            // 拿到 URL 后立即关闭流，不下载图片数据，省流量
            (response.data as ResponseBody).close(); 
          } catch (e2) {
            return null;
          }
        }

        if (finalUrl == null) return null;

        // 3. 参数净化 (Clean Up)
        // 如果最终 URL 里居然还带着我们传的 _t 参数，说明服务器把参数透传回来了
        // 这会导致缓存失效，所以我们要把它洗掉
        final uri = Uri.parse(finalUrl);
        if (uri.queryParameters.containsKey('_t') || uri.queryParameters.containsKey('_r')) {
           final newQueryParams = Map<String, String>.from(uri.queryParameters);
           newQueryParams.remove('_t');
           newQueryParams.remove('_r');
           finalUrl = uri.replace(queryParameters: newQueryParams).toString();
        }

        // 4. 死循环防御
        // 如果最终 URL 和原始请求 URL (去掉随机参数后) 一模一样
        // 说明服务器根本没重定向，而是直接返回了图片 (Status 200)
        // 这种图源无法做到“锁定”，每次请求都会变，我们在 ID 上做个标记
        // 但对于 LuvBree 这种 API，它是会重定向的，所以 finalUrl 会变成 .../xxx.jpg
        
        return finalUrl;

      } catch (e) {
        return null;
      }
    });

    final results = await Future.wait(futures);
    
    final List<UniWallpaper> wallpapers = [];
    for (var url in results) {
      if (url != null && url.startsWith('http')) {
        // 简单去重
        if (!wallpapers.any((w) => w.fullUrl == url)) {
          // 🔥 关键：用最终锁定的 URL 作为 ID
          // 只要 URL 没变，Flutter 的 CachedNetworkImage 就会用缓存
          // 详情页和下载也会用这个 URL，保证是同一张图
          wallpapers.add(UniWallpaper(
            id: url.hashCode.toString(), 
            sourceId: rule.id,
            thumbUrl: url, // 锁定后的 URL
            fullUrl: url,  // 锁定后的 URL
            width: 0, 
            height: 0,
          ));
        }
      }
    }
    return wallpapers;
  }

  Future<List<UniWallpaper>> _fetchJsonMode(SourceRule rule, Map<String, dynamic> params) async {
    final response = await _dio.get(
      rule.url,
      queryParameters: params,
      options: Options(
        headers: rule.headers ?? {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
      T? getValue<T>(String path, dynamic source) {
        try {
          if (path == '.') return source as T;
          if (!path.contains(r'$')) return source[path] as T?;
          final p = JsonPath(path);
          return p.read(source).firstOrNull?.value as T?;
        } catch (e) {
          return null;
        }
      }

      final id = getValue<String>(rule.idPath, item) ?? DateTime.now().toString();
      String thumb = getValue<String>(rule.thumbPath, item) ?? "";
      String full = getValue<String>(rule.fullPath, item) ?? thumb;
      
      if (rule.imagePrefix != null && rule.imagePrefix!.isNotEmpty) {
        if (!thumb.startsWith('http')) thumb = rule.imagePrefix! + thumb;
        if (!full.startsWith('http')) full = rule.imagePrefix! + full;
      }

      final width = getValue<int>(rule.widthPath ?? '', item) ?? 0;
      final height = getValue<int>(rule.heightPath ?? '', item) ?? 0;
      final grade = getValue<String>(rule.gradePath ?? '', item);

      return UniWallpaper(
        id: id.toString(),
        sourceId: rule.id,
        thumbUrl: thumb,
        fullUrl: full,
        width: width.toDouble(),
        height: height.toDouble(),
        grade: grade,
      );
    }).toList();
  }
}
