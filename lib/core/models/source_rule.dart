// lib/core/models/source_rule.dart
import 'dart:convert';

class SourceRule {
  final String id;
  final String name;
  final String url;
  final Map<String, String>? headers;
  final Map<String, dynamic>? fixedParams;
  
  // 🔥 新增：API Key (用于 Wallhaven 等需要密钥的图源)
  final String? apiKey;
  
  final List<SourceFilter>? filters;
  
  final String paramPage;
  final String paramKeyword;
  
  final String listPath;
  final String idPath;
  final String thumbPath;
  final String fullPath;
  final String? widthPath;
  final String? heightPath;
  final String? imagePrefix;

  SourceRule({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.fixedParams,
    this.apiKey, // 新增
    this.filters,
    this.paramPage = 'page',
    this.paramKeyword = 'q',
    required this.listPath,
    required this.idPath,
    required this.thumbPath,
    required this.fullPath,
    this.widthPath,
    this.heightPath,
    this.imagePrefix,
  });

  factory SourceRule.fromJson(Map<String, dynamic> map) {
    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',
      headers: map['headers'] != null ? Map<String, String>.from(map['headers']) : null,
      fixedParams: map['fixed_params'],
      // 🔥 解析 apiKey
      apiKey: map['api_key'],
      filters: map['filters'] != null 
          ? (map['filters'] as List).map((e) => SourceFilter.fromJson(e)).toList() 
          : null,
      paramPage: map['params']?['page'] ?? 'page',
      paramKeyword: map['params']?['keyword'] ?? 'q',
      listPath: map['parser']?['list'] ?? r'$',
      idPath: map['parser']?['id'] ?? 'id',
      thumbPath: map['parser']?['thumb'] ?? 'url',
      fullPath: map['parser']?['full'] ?? 'url',
      widthPath: map['parser']?['width'],
      heightPath: map['parser']?['height'],
      imagePrefix: map['parser']?['image_prefix'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers,
      'fixed_params': fixedParams,
      'api_key': apiKey, // 序列化
      'filters': filters?.map((e) => e.toJson()).toList(),
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
        'image_prefix': imagePrefix,
      }
    };
  }
}

class SourceFilter {
  final String key;
  final String name;
  final String type;
  final List<FilterOption> options;

  SourceFilter({required this.key, required this.name, required this.type, required this.options});

  factory SourceFilter.fromJson(Map<String, dynamic> json) {
    return SourceFilter(
      key: json['key'],
      name: json['name'],
      type: json['type'] ?? 'radio',
      options: (json['options'] as List).map((e) => FilterOption.fromJson(e)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key, 'name': name, 'type': type,
    'options': options.map((e) => e.toJson()).toList()
  };
}

class FilterOption {
  final String name;
  final String value;

  FilterOption({required this.name, required this.value});

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(name: json['name'], value: json['value']);
  }

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
}
