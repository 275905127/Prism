// lib/core/engine/rule_engine.dart
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

// ignore_for_file: avoid_print

class RuleEngine {
  final Dio _dio = Dio();

  RuleEngine() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  Future<List<UniWallpaper>> fetch(SourceRule rule, {int page = 1, String? query}) async {
    try {
      // 1. 处理 URL 变量替换
      String safeQuery = query ?? '';
      // 如果是首页（query为空），且 URL 里强制要求 query，我们可以给个默认值，或者依靠服务端宽容处理
      // 这里我们简单处理：直接替换
      String path = rule.search.url
          .replaceAll('{page}', page.toString())
          .replaceAll('{query}', safeQuery);
      
      // 2. 拼接 BaseURL (处理斜杠堆叠问题)
      String fullUrl = rule.baseUrl;
      if (!fullUrl.endsWith('/') && !path.startsWith('/')) {
        fullUrl += '/$path';
      } else {
        fullUrl += path;
      }

      // 3. 准备请求头 (Headers)
      // 如果规则里没配 User-Agent，给它一个默认的，防止被服务器当成爬虫拒接
      final Map<String, dynamic> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ...?rule.headers, // 合并规则里的 Headers
      };

      print('🔮 Engine: GET $fullUrl');
      print('   Headers: ${rule.headers}');
      print('   Params: ${rule.search.params}');

      // 4. 发起请求
      final response = await _dio.get(
        fullUrl,
        queryParameters: rule.search.params, // Dio 会自动处理 ?key=value
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
        ),
      );

      // 5. 解析数据
      final listPath = JsonPath(rule.parser.listNode);
      final rawList = listPath.read(response.data);

      List<UniWallpaper> results = [];

      for (var match in rawList) {
        final item = match.value;
        if (item is! Map) continue;

        String id = _extractString(item, rule.parser.id);
        String thumb = _extractString(item, rule.parser.thumb);
        String full = _extractString(item, rule.parser.full);

        // 处理 URL 前缀
        if (rule.parser.thumbPrefix != null && thumb.isNotEmpty && !thumb.startsWith('http')) {
          thumb = rule.parser.thumbPrefix! + thumb;
        }
        if (rule.parser.fullPrefix != null && full.isNotEmpty && !full.startsWith('http')) {
          full = rule.parser.fullPrefix! + full;
        }

        double w = _extractDouble(item, rule.parser.width);
        double h = _extractDouble(item, rule.parser.height);

        if (thumb.isEmpty) continue;

        results.add(UniWallpaper(
          id: id,
          thumbUrl: thumb,
          fullUrl: full,
          width: w,
          height: h,
          sourceId: rule.id,
          // 🔥 关键：把 headers 传给图片，否则图片加载组件不知道用什么 Referer
          metadata: {
             if (rule.headers != null) 'headers': rule.headers.toString()
          },
        ));
      }

      print('✅ Parsed ${results.length} items.');
      return results;

    } catch (e) {
      print('❌ Engine Error: $e');
      rethrow;
    }
  }

  String _extractString(Map data, String path) {
    final val = _resolvePath(data, path);
    return val?.toString() ?? '';
  }

  double _extractDouble(Map data, String path) {
    final val = _resolvePath(data, path);
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }

  dynamic _resolvePath(Map data, String path) {
    final keys = path.split('.');
    dynamic current = data;
    for (var key in keys) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }
}