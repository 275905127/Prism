// lib/core/models/source_rule.dart
class SourceRule {
  final String id;
  final String name;
  final String url;

  /// 规则自带 headers（静态）
  final Map<String, String>? headers;

  final Map<String, dynamic>? fixedParams;

  /// 保存原始 key
  final String? apiKey;

  /// apiKey 放哪、叫什么、前缀
  /// api_key_in: 'query' | 'header'
  final String? apiKeyName;
  final String apiKeyIn;
  final String apiKeyPrefix;

  /// ✅ 新增：keyword 策略（通用关键）
  final String? defaultKeyword;
  final bool keywordRequired;

  final List<SourceFilter>? filters;

  // 响应类型 ('json' or 'random')
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

    /// ✅ new
    this.defaultKeyword,
    this.keywordRequired = false,

    this.filters,
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

      /// ✅ new
      defaultKeyword: map['default_keyword'],
      keywordRequired: map['keyword_required'] ?? false,

      filters: map['filters'] != null
          ? (map['filters'] as List).map((e) => SourceFilter.fromJson(e)).toList()
          : null,

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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': responseType,

      'headers': headers,
      'fixed_params': fixedParams,

      'api_key': apiKey,
      'api_key_name': apiKeyName,
      'api_key_in': apiKeyIn,
      'api_key_prefix': apiKeyPrefix,

      /// ✅ new
      'default_keyword': defaultKeyword,
      'keyword_required': keywordRequired,

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
        'grade': gradePath,
      }
    };
  }
}

// ↓↓↓ 下面 SourceFilter / FilterOption 保持你原来的不变