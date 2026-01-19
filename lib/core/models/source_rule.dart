// lib/core/models/source_rule.dart

class SourceRule {
  final String id;
  final String name;
  final String url;

  final Map<String, String>? headers;
  final Map<String, dynamic>? fixedParams;

  final String? apiKey;
  final String? apiKeyName;
  final String apiKeyIn;      // 'query' | 'header'
  final String apiKeyPrefix;  // e.g. 'Bearer '

  final List<SourceFilter> filters;

  final String responseType;  // 'json' | 'random'
  final String paramPage;     // page param name, can be '' to disable
  final String paramKeyword;  // keyword param name, can be '' to disable

  final String listPath;
  final String idPath;
  final String thumbPath;
  final String fullPath;
  final String? widthPath;
  final String? heightPath;
  final String? imagePrefix;
  final String? gradePath;

  final bool keywordRequired;
  final String? defaultKeyword;

  const SourceRule({
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

  // --------- helpers (private) ---------

  static Map<String, String>? _parseHeaders(dynamic raw) {
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k == null) return;
      out[k.toString()] = v?.toString() ?? '';
    });
    return out;
    }

  static Map<String, dynamic>? _parseMapDyn(dynamic raw) {
    if (raw is! Map) return null;
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (k == null) return;
      out[k.toString()] = v;
    });
    return out;
  }

  static String _normalizeApiKeyIn(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    return (s == 'header') ? 'header' : 'query';
  }

  static String _normalizeResponseType(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    return (s == 'random') ? 'random' : 'json';
  }

  factory SourceRule.fromJson(Map<String, dynamic> map) {
    // ✅ 兼容 fixed_params / fixedParams
    final fixed = map.containsKey('fixed_params')
        ? map['fixed_params']
        : map['fixedParams'];

    // ✅ 兼容 type / responseType
    final type = map.containsKey('type') ? map['type'] : map['responseType'];

    // ✅ 兼容 params = {} 不存在时
    final params = (map['params'] is Map) ? map['params'] as Map : const {};

    // ✅ 兼容 parser = {} 不存在时
    final parser = (map['parser'] is Map) ? map['parser'] as Map : const {};

    // ✅ 兼容 filters 脏数据（只接受 Map）
    final rawFilters = map['filters'];
    final List<SourceFilter> parsedFilters = [];
    if (rawFilters is List) {
      for (final e in rawFilters) {
        if (e is Map) {
          try {
            parsedFilters.add(SourceFilter.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // skip bad filter
          }
        }
      }
    }

    return SourceRule(
      id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: map['name'] ?? '未命名图源',
      url: map['url'] ?? '',

      // ✅ headers 容错：value toString
      headers: _parseHeaders(map['headers']),

      // ✅ fixed_params 容错 + 兼容
      fixedParams: _parseMapDyn(fixed),

      apiKey: map['api_key'],
      apiKeyName: map['api_key_name'],

      // ✅ apiKeyIn 收敛
      apiKeyIn: _normalizeApiKeyIn(map['api_key_in']),
      apiKeyPrefix: (map['api_key_prefix'] ?? '').toString(),

      filters: parsedFilters,

      // ✅ type 收敛 + 兼容
      responseType: _normalizeResponseType(type),

      // ✅ params 里允许 ''（显式禁用），所以这里用 toString 保留空串
      paramPage: (params['page'] ?? 'page').toString(),
      paramKeyword: (params['keyword'] ?? 'q').toString(),

      // ✅ parser 同理
      listPath: (parser['list'] ?? r'$').toString(),
      idPath: (parser['id'] ?? 'id').toString(),
      thumbPath: (parser['thumb'] ?? 'url').toString(),
      fullPath: (parser['full'] ?? 'url').toString(),
      widthPath: parser['width']?.toString(),
      heightPath: parser['height']?.toString(),
      imagePrefix: parser['image_prefix']?.toString(),
      gradePath: parser['grade']?.toString(),

      keywordRequired: map['keyword_required'] ?? false,
      defaultKeyword: map['default_keyword']?.toString(),
    );
  }

  /// ✅ 关键：给 SourceManager 存储用（r.toJson()）
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

      'keyword_required': keywordRequired,
      'default_keyword': defaultKeyword,

      'filters': filters.map((e) => e.toJson()).toList(),

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
  /// 给图片加载用：把 rule.headers + apiKey(header 模式) 合并
  Map<String, String> buildRequestHeaders() {
    final h = <String, String>{
      "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      ...?headers,
    };

    final k = apiKey;
    if (k != null && k.isNotEmpty && apiKeyIn == 'header') {
      final keyName = (apiKeyName == null || apiKeyName!.isEmpty) ? 'apikey' : apiKeyName!;
      h[keyName] = '$apiKeyPrefix$k';
    }
    return h;
  }
}

class SourceFilter {
  final String key;
  final String name;
  final String type;       // 'radio' | 'checklist'
  final String separator;  // join 时使用
  final String encode;     // 'join' | 'repeat' | 'merge'
  final List<FilterOption> options;

  const SourceFilter({
    required this.key,
    required this.name,
    required this.type,
    this.separator = ',',
    this.encode = 'join',
    required this.options,
  });

  static String _normalizeType(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    return (s == 'checklist') ? 'checklist' : 'radio';
  }

  static String _normalizeEncode(dynamic v) {
    final s = (v ?? '').toString().toLowerCase().trim();
    if (s == 'repeat') return 'repeat';
    if (s == 'merge') return 'merge';
    return 'join';
  }

  factory SourceFilter.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final List<FilterOption> parsed = [];

    if (rawOptions is List) {
      for (final e in rawOptions) {
        if (e is Map) {
          try {
            parsed.add(FilterOption.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // skip bad option
          }
        }
      }
    }

    return SourceFilter(
      key: (json['key'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: _normalizeType(json['type']),
      separator: (json['separator'] ?? ',').toString(),
      encode: _normalizeEncode(json['encode']),
      options: parsed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'type': type,
      'separator': separator,
      'encode': encode,
      'options': options.map((e) => e.toJson()).toList(),
    };
  }
}

class FilterOption {
  final String name;
  final String value;

  const FilterOption({
    required this.name,
    required this.value,
  });

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(
      name: (json['name'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'value': value};
  }
}