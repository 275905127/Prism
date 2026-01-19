class SourceRule {
  final String id;
  final String name;
  final String url;

  final Map<String, String>? headers;
  final Map<String, dynamic>? fixedParams;

  final String? apiKey;
  final String? apiKeyName;
  final String apiKeyIn;
  final String apiKeyPrefix;

  final List<SourceFilter> filters;

  final String responseType;
  final String paramPage;
  final String paramKeyword;

  final String listPath;
  final String idPath;
  final String thumbPath;
  final String fullPath;
  final String? widthPath;
  final String? heightPath;
  final String? imagePrefix;
  final String? gradePath;

  // 🔒 先给默认值，避免你后面再炸
  final bool keywordRequired;
  final String? defaultKeyword;

  SourceRule({
    required this.id,
    required this.name,
    required this.url,
    this.headers,
    this.fixedParams,
    this.apiKey,
    this.apiKeyName,
    this.apiKeyIn = 'query',
    this.apiKeyPrefix = '',
    this.filters = const [],
    this.responseType = 'json',
    this.paramPage = 'page',
    this.paramKeyword = 'q',
    required this.listPath,
    required this.idPath,
    required this.thumbPath,
    required this.fullPath,
    this.widthPath,
    this.heightPath,
    this.imagePrefix,
    this.gradePath,
    this.keywordRequired = false,
    this.defaultKeyword,
  });

  factory SourceRule.fromJson(Map<String, dynamic> map) {
    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',
      headers: map['headers'] != null ? Map<String, String>.from(map['headers']) : null,
      fixedParams: map['fixed_params'],
      apiKey: map['api_key'],
      apiKeyName: map['api_key_name'],
      apiKeyIn: map['api_key_in'] ?? 'query',
      apiKeyPrefix: map['api_key_prefix'] ?? '',
      filters: (map['filters'] as List? ?? [])
          .map((e) => SourceFilter.fromJson(e))
          .toList(),
      responseType: map['type'] ?? 'json',
      paramPage: map['params']?['page'] ?? 'page',
      paramKeyword: map['params']?['keyword'] ?? 'q',
      listPath: map['parser']?['list'] ?? r'$',
      idPath: map['parser']?['id'] ?? 'id',
      thumbPath: map['parser']?['thumb'] ?? 'url',
      fullPath: map['parser']?['full'] ?? 'url',
      widthPath: map['parser']?['width'],
      heightPath: map['parser']?['height'],
      imagePrefix: map['parser']?['image_prefix'],
      gradePath: map['parser']?['grade'],
      keywordRequired: map['keyword_required'] ?? false,
      defaultKeyword: map['default_keyword'],
    );
  }
}

class SourceFilter {
  final String key;
  final String name;
  final String type;        // radio / checklist
  final String separator;
  final String encode;      // join / repeat / merge
  final List<FilterOption> options;

  SourceFilter({
    required this.key,
    required this.name,
    required this.type,
    this.separator = ',',
    this.encode = 'join',
    required this.options,
  });

  factory SourceFilter.fromJson(Map<String, dynamic> json) {
    return SourceFilter(
      key: json['key'],
      name: json['name'],
      type: json['type'] ?? 'radio',
      separator: json['separator'] ?? ',',
      encode: json['encode'] ?? 'join',
      options: (json['options'] as List? ?? [])
          .map((e) => FilterOption.fromJson(e))
          .toList(),
    );
  }
}

class FilterOption {
  final String name;
  final String value;

  FilterOption({
    required this.name,
    required this.value,
  });

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(
      name: json['name'] ?? '',
      value: json['value'] ?? '',
    );
  }
}