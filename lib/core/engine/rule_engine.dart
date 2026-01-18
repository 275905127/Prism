// lib/core/engine/rule_engine.dart
import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';
import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';

class RuleEngine {
  final Dio _dio = Dio();

  Future<List<UniWallpaper>> fetch(SourceRule rule, {int page = 1, String? query}) async {
    try {
      final Map<String, dynamic> params = {
        rule.paramPage: page,
      };
      if (query != null && query.isNotEmpty) {
        params[rule.paramKeyword] = query;
      }

      final response = await _dio.get(
        rule.url,
        queryParameters: params,
        options: Options(
          // 伪装头
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
      
      if (match == null || match.value is! List) {
        return [];
      }

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
        final thumb = getValue<String>(rule.thumbPath, item) ?? "";
        final full = getValue<String>(rule.fullPath, item) ?? thumb;
        final width = getValue<int>(rule.widthPath ?? '', item) ?? 1080;
        final height = getValue<int>(rule.heightPath ?? '', item) ?? 1920;

        return UniWallpaper(
          id: id.toString(),
          sourceId: rule.id, // 🔥 修复：补上了这个必填参数
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
