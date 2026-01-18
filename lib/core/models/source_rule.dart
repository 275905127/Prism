// lib/core/models/source_rule.dart
import 'dart:convert';

class SourceRule {
  final String id;
  final String name;
  final String url;
  final Map<String, String>? headers;
  
  // 🔥 新增：固定参数 (例如 apikey=xxx, purity=110)
  final Map<String, dynamic>? fixedParams;
  
  final String paramPage;
  final String paramKeyword;
  
  final String listPath;
  final String idPath;
  final String thumbPath;
  final String fullPath;
  final String? widthPath;
  final String? heightPath;
  
  // 🔥 新增：图片 URL 前缀 (例如 https://cn.bing.com)
  final String? imagePrefix;

  SourceRule({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.fixedParams, // 新增
    this.paramPage = 'page',
    this.paramKeyword = 'q',
    required this.listPath,
    required this.idPath,
    required this.thumbPath,
    required this.fullPath,
    this.widthPath,
    this.heightPath,
    this.imagePrefix, // 新增
  });

  factory SourceRule.fromJson(Map<String, dynamic> map) {
    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',
      headers: map['headers'] != null ? Map<String, String>.from(map['headers']) : null,
      // 解析固定参数
      fixedParams: map['fixed_params'],
      paramPage: map['params']?['page'] ?? 'page',
      paramKeyword: map['params']?['keyword'] ?? 'q',
      listPath: map['parser']?['list'] ?? r'$',
      idPath: map['parser']?['id'] ?? 'id',
      thumbPath: map['parser']?['thumb'] ?? 'url',
      fullPath: map['parser']?['full'] ?? 'url',
      widthPath: map['parser']?['width'],
      heightPath: map['parser']?['height'],
      // 解析前缀
      imagePrefix: map['parser']?['image_prefix'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers,
      'fixed_params': fixedParams, // 序列化
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
        'image_prefix': imagePrefix, // 序列化
      }
    };
  }
}
