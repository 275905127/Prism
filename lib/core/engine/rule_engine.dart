// lib/core/engine/rule_engine.dart
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class RuleEngine {
  final Dio _dio = Dio();

  Future<List<UniWallpaper>> fetch(SourceRule rule, {int page = 1, String? query}) async {
    try {
      // 1. 构造参数
      final Map<String, dynamic> params = {
        rule.paramPage: page,
      };
      if (query != null && query.isNotEmpty) {
        params[rule.paramKeyword] = query;
      }

      // 2. 发起请求 (🔥 带上 Headers)
      final response = await _dio.get(
        rule.url,
        queryParameters: params,
        options: Options(
          headers: rule.headers ?? {
            // 默认伪装成 Chrome，防止被直接拦截
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
          },
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      // 3. 解析数据
      final jsonMap = response.data;
      
      // 使用 JSONPath 提取列表
      final listPath = JsonPath(rule.listPath);
      final match = listPath.read(jsonMap).firstOrNull;
      
      if (match == null || match.value is! List) {
        return [];
      }

      final List list = match.value as List;
      
      // 4. 映射为对象
      return list.map((item) {
        // 辅助函数：根据路径提取值
        T? getValue<T>(String path, dynamic source) {
          try {
            // 如果路径是 "."，直接返回自身
            if (path == '.') return source as T;
            // 简单路径直接取 (性能优化)
            if (!path.contains(r'$')) return source[path] as T?;
            // 复杂路径用 JsonPath
            final p = JsonPath(path);
            return p.read(source).firstOrNull?.value as T?;
          } catch (e) {
            return null;
          }
        }

        final id = getValue<String>(rule.idPath, item) ?? DateTime.now().toString();
        final thumb = getValue<String>(rule.thumbPath, item) ?? "";
        final full = getValue<String>(rule.fullPath, item) ?? thumb;
        final width = getValue<int>(rule.widthPath ?? '', item) ?? 1080;
        final height = getValue<int>(rule.heightPath ?? '', item) ?? 1920;

        return UniWallpaper(
          id: id.toString(),
          thumbUrl: thumb,
          fullUrl: full,
          width: width.toDouble(),
          height: height.toDouble(),
        );
      }).toList();

    } catch (e) {
      print("Engine Error: $e");
      rethrow;
    }
  }
}
