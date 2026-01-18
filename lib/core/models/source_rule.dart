// lib/core/models/source_rule.dart
class SourceRule {
  final String id;
  final String name;
  final String baseUrl;
  final SearchConfig search;
  final ParseConfig parser;
  // 🔥 新增：全局请求头 (用于伪装浏览器，解决 403 Forbidden)
  final Map<String, String>? headers;

  SourceRule({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.search,
    required this.parser,
    this.headers,
  });

  factory SourceRule.fromJson(Map<String, dynamic> json) {
    return SourceRule(
      id: json['id'],
      name: json['name'],
      baseUrl: json['base_url'],
      search: SearchConfig.fromJson(json['search']),
      parser: ParseConfig.fromJson(json['parser']),
      headers: json['headers'] != null 
          ? Map<String, String>.from(json['headers']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'search': search.toJson(),
      'parser': parser.toJson(),
      if (headers != null) 'headers': headers,
    };
  }
}

class SearchConfig {
  final String url;
  // 🔥 新增：固定参数 (例如 apikey=123, safe_mode=true)
  final Map<String, dynamic>? params;
  
  SearchConfig({required this.url, this.params});

  factory SearchConfig.fromJson(Map<String, dynamic> json) => SearchConfig(
    url: json['url'],
    params: json['params'],
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    if (params != null) 'params': params,
  };
}

class ParseConfig {
  final String listNode;
  final String id;
  final String thumb;
  final String full;
  final String width;
  final String height;
  final String? thumbPrefix;
  final String? fullPrefix;

  ParseConfig({
    required this.listNode,
    required this.id,
    required this.thumb,
    required this.full,
    required this.width,
    required this.height,
    this.thumbPrefix,
    this.fullPrefix,
  });

  factory ParseConfig.fromJson(Map<String, dynamic> json) {
    return ParseConfig(
      listNode: json['list_node'],
      id: json['id'],
      thumb: json['thumb'],
      full: json['full'],
      width: json['width'],
      height: json['height'],
      thumbPrefix: json['thumb_prefix'],
      fullPrefix: json['full_prefix'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'list_node': listNode,
      'id': id,
      'thumb': thumb,
      'full': full,
      'width': width,
      'height': height,
      'thumb_prefix': thumbPrefix,
      'full_prefix': fullPrefix,
    };
  }
}