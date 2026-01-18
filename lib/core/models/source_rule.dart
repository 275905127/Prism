// lib/core/models/source_rule.dart
import 'dart:convert';

class SourceRule {
  final String id;
  final String name;
  final String url;
  final Map<String, String>? headers; // 请求头
  final String paramPage;
  final String paramKeyword;
  
  // JSONPath 字段
  final String listPath;
  final String idPath;
  final String thumbPath;
  final String fullPath;
  final String? widthPath;
  final String? heightPath;

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

  // 🔥 修复：这里改回接收 Map<String, dynamic>
  factory SourceRule.fromJson(Map<String, dynamic> map) {
    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',
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
