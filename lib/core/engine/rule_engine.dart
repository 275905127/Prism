// lib/core/engine/rule_engine.dart
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
    // 构造基础参数
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
    // 搜索词只在非 Random 模式或 Random 接口支持参数时才加
    if (query != null && query.isNotEmpty) {
      params[rule.paramKeyword] = query;
    }

    try {
      // 🔥 分支 1: 直链随机模式 (Random Direct Link)
      if (rule.responseType == 'random') {
        return await _fetchRandomMode(rule, params);
      } 
      // 🔥 分支 2: 标准 JSON 模式
      else {
        // 对于 JSON 模式，才需要分页参数
        params[rule.paramPage] = page;
        return await _fetchJsonMode(rule, params);
      }
    } catch (e) {
      print("Engine Error: $e");
      rethrow;
    }
  }

  // 🔥 新增：处理直链随机图源
  Future<List<UniWallpaper>> _fetchRandomMode(SourceRule rule, Map<String, dynamic> params) async {
    // 并发数：一次请求 12 张，凑满一页
    const int batchSize = 12;
    
    // 创建 12 个并发任务
    final futures = List.generate(batchSize, (_) async {
      try {
        final response = await _dio.head( // 使用 HEAD 请求，只拿 Header 不下载图片，速度极快
          rule.url,
          queryParameters: params,
          options: Options(
            headers: rule.headers,
            followRedirects: true, // 跟随重定向，拿到最终 URL
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        // 获取最终的真实 URL
        return response.realUri.toString();
      } catch (e) {
        return null;
      }
    });

    // 等待所有请求完成
    final results = await Future.wait(futures);
    
    // 过滤掉失败的，并转换为 UniWallpaper
    final List<UniWallpaper> wallpapers = [];
    for (var url in results) {
      if (url != null && url.startsWith('http')) {
        // 随机图源通常不知道宽高，设为 0 让 UI 自己适配
        wallpapers.add(UniWallpaper(
          id: url.hashCode.toString(), // 用 URL 的 Hash 做临时 ID
          sourceId: rule.id,
          thumbUrl: url,
          fullUrl: url,
          width: 0, 
          height: 0,
        ));
      }
    }
    return wallpapers;
  }

  // 处理标准 JSON 模式 (原来的逻辑)
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
