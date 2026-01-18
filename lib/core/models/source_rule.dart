// lib/core/models/source_rule.dart
import 'dart:convert';

class SourceRule {
  final String id;
  final String name;
  final String url; // API 地址
  final Map<String, String>? headers; // 🔥 新增: 请求头 (User-Agent, Cookie 等)
  final String paramPage; // 分页参数名 (如 "page" 或 "p")
  final String paramKeyword; // 搜索参数名 (如 "q" 或 "query")
  
  // JSONPath 规则
  final String listPath;   // 列表路径 (如 "data")
  final String idPath;     // ID 路径
  final String thumbPath;  // 缩略图路径
  final String fullPath;   // 原图路径
  final String? widthPath; // 宽度路径 (可选)
  final String? heightPath;// 高度路径 (可选)

  SourceRule({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.paramPage = 'page',
    this.paramKeyword = 'q',
    required this.listPath,
    required this.idPath,
    required this.thumbPath,
    required this.fullPath,
    this.widthPath,
    this.heightPath,
  });

  factory SourceRule.fromJson(String jsonStr) {
    final Map<String, dynamic> map = json.decode(jsonStr);
    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',
      // 🔥 解析 Headers
      headers: map['headers'] != null ? Map<String, String>.from(map['headers']) : null,
      paramPage: map['params']?['page'] ?? 'page',
      paramKeyword: map['params']?['keyword'] ?? 'q',
      listPath: map['parser']?['list'] ?? r'$',
      idPath: map['parser']?['id'] ?? 'id',
      thumbPath: map['parser']?['thumb'] ?? 'url',
      fullPath: map['parser']?['full'] ?? 'url',
      widthPath: map['parser']?['width'],
      heightPath: map['parser']?['height'],
    );
  }

  // 序列化回 JSON (方便调试或保存)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers,
      'params': {
        'page': paramPage,
        'keyword': paramKeyword,
      },
      'parser': {
        'list': listPath,
        'id': idPath,
        'thumb': thumbPath,
        'full': fullPath,
        'width': widthPath,
        'height': heightPath,
      }
    };
  }
}
