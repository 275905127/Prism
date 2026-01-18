// lib/core/engine/rule_engine.dart
import 'dart:math'; // 引入随机数
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

  // 🔥 核心修改：温和的随机图获取策略
  Future<List<UniWallpaper>> _fetchRandomMode(SourceRule rule, Map<String, dynamic> params) async {
    // 1. 降低并发数：从 12 降为 6 (避免瞬间高频，保护 IP)
    const int batchSize = 6; 
    
    // 2. 错峰延迟：每张图之间间隔 300ms (模仿人类点击频率)
    const int delayMs = 300; 

    final futures = List.generate(batchSize, (index) async {
      // 关键点：根据索引计算延迟时间 (0ms, 300ms, 600ms, 900ms...)
      await Future.delayed(Duration(milliseconds: index * delayMs));

      try {
        // 3. 防缓存/防重复：添加随机数或时间戳
        // 很多 API 如果发现请求参数完全一样，会直接返回缓存的同一张图
        // 或者认为你是脚本重放，从而拒绝服务。
        final requestParams = Map<String, dynamic>.from(params);
        requestParams['_t'] = DateTime.now().millisecondsSinceEpoch + index;
        requestParams['_r'] = Random().nextInt(10000); 

        final response = await _dio.head(
          rule.url,
          queryParameters: requestParams, // 带上随机参数
          options: Options(
            headers: rule.headers,
            followRedirects: true,
            sendTimeout: const Duration(seconds: 8), // 稍微放宽超时
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (status) => status != null && status < 400, // 遇到 404/429 视为错误
          ),
        );
        return response.realUri.toString();
      } catch (e) {
        // 如果遇到 429 Too Many Requests，建议可以在这里做一个标记，停止后续请求
        // 目前简单处理：返回 null，跳过这一张
        return null;
      }
    });

    final results = await Future.wait(futures);
    
    final List<UniWallpaper> wallpapers = [];
    for (var url in results) {
      if (url != null && url.startsWith('http')) {
        // 简单的去重逻辑 (防止万一 API 还是返回了重复图)
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
