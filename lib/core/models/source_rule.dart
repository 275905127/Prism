// lib/core/models/source_rule.dart

class SourceRule {
  final String id;
  final String name;
  final String url;

  final Map<String, String>? headers;
  final Map<String, dynamic>? fixedParams;

  final String? apiKey;
  final String? apiKeyName;
  final String apiKeyIn; // 'query' | 'header'
  final String apiKeyPrefix; // e.g. 'Bearer '

  final List<SourceFilter> filters;

  final String responseType; // 'json' | 'random'
  final String paramPage; // page param name, can be '' to disable
  final String paramKeyword; // keyword param name, can be '' to disable

  // ✅ 新增：分页模式
  // 'page'   : page=1,2,3...
  // 'offset' : paramPage = offset/start = (page-1)*pageSize
  // 'cursor' : paramPage = cursor/after，page>1 从上次响应读出来继续
  final String pageMode; // 'page' | 'offset' | 'cursor'
  final int pageSize; // offset 模式用；0 表示自动猜测（per_page/limit/rows/...)
  final String? cursorPath; // cursor 模式用：从响应里读下一页游标

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

  // ============================================================
  // ✅ 两阶段模型：Stage 1 原始字段抓取（支持通配/多候选路径）
  // - 兼容旧规则：全部是可选字段；没配就不影响任何行为
  // - 支持写法：
  //    1) "uploaderPath": "user.name"
  //    2) "uploaderPath": ["uploader","user","author.name"]
  //    3) "uploaderPath": "uploader|user|author.name"
  // ============================================================

  /// 详情补全接口（可选）。支持 {id} 占位符。
  /// 例如：https://api.xxx.com/wallpaper/{id}
  final String? detailUrl;

  /// 详情返回数据的根节点（可选，默认 "." / "$" 都可）。
  /// 若使用 JsonPath：用 "$.data"；若使用 dot-path：用 "data"
  final String? detailRootPath;

  final List<String> uploaderPathCandidates;
  final List<String> viewsPathCandidates;
  final List<String> favoritesPathCandidates;
  final List<String> fileSizePathCandidates;
  final List<String> createdAtPathCandidates;
  final List<String> mimeTypePathCandidates;

  /// tags：允许返回 list 或 string（string 时会自动 split）
  final List<String> tagsPathCandidates;

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

    // ✅ 新增字段默认值：不影响旧规则
    this.pageMode = 'page',
    this.pageSize = 0,
    this.cursorPath,

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

    // ✅ 两阶段模型字段（全可选，默认空列表）
    this.detailUrl,
    this.detailRootPath,
    this.uploaderPathCandidates = const [],
    this.viewsPathCandidates = const [],
    this.favoritesPathCandidates = const [],
    this.fileSizePathCandidates = const [],
    this.createdAtPathCandidates = const [],
    this.mimeTypePathCandidates = const [],
    this.tagsPathCandidates = const [],
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

  static List<SourceFilter> _parseFilters(dynamic raw) {
    if (raw is! List) return const <SourceFilter>[];
    final out = <SourceFilter>[];
    for (final it in raw) {
      if (it is Map) {
        out.add(SourceFilter.fromJson(it.map((k, v) => MapEntry(k.toString(), v))));
      }
    }
    return out;
  }

  static bool _asBool(dynamic v, {bool def = false}) {
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
    return def;
  }

  static int _asInt(dynamic v, {int def = 0}) {
    if (v is int) return v;
    final n = int.tryParse(v?.toString() ?? '');
    return n ?? def;
  }

  static String _asString(dynamic v, {String def = ''}) {
    final s = v?.toString() ?? '';
    return s.trim().isEmpty ? def : s;
  }

  /// ✅ 通配解析：支持 String / List / "a|b|c"
  static List<String> _parsePathCandidates(dynamic raw) {
    if (raw == null) return const <String>[];
    if (raw is List) {
      return raw.map((e) => (e?.toString() ?? '').trim()).where((s) => s.isNotEmpty).toList();
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return const <String>[];
    // 支持 a|b|c
    if (s.contains('|')) {
      return s.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return <String>[s];
  }

  // -------------------- json --------------------

  factory SourceRule.fromJson(Map<String, dynamic> json) {
    return SourceRule(
      id: _asString(json['id']),
      name: _asString(json['name'], def: _asString(json['id'])),
      url: _asString(json['url']),
      headers: _parseHeaders(json['headers']),
      fixedParams: _parseMapDyn(json['fixed_params'] ?? json['fixedParams']),
      apiKey: (json['api_key'] ?? json['apiKey'])?.toString(),
      apiKeyName: (json['api_key_name'] ?? json['apiKeyName'])?.toString(),
      apiKeyIn: _asString(json['api_key_in'] ?? json['apiKeyIn'], def: 'query'),
      apiKeyPrefix: _asString(json['api_key_prefix'] ?? json['apiKeyPrefix'], def: ''),
      filters: _parseFilters(json['filters']),
      responseType: _asString(json['response_type'] ?? json['responseType'], def: 'json'),
      paramPage: _asString(json['param_page'] ?? json['paramPage'], def: 'page'),
      paramKeyword: _asString(json['param_keyword'] ?? json['paramKeyword'], def: 'q'),

      pageMode: _asString(json['page_mode'] ?? json['pageMode'], def: 'page'),
      pageSize: _asInt(json['page_size'] ?? json['pageSize'], def: 0),
      cursorPath: (json['cursor_path'] ?? json['cursorPath'])?.toString(),

      listPath: _asString(json['list_path'] ?? json['listPath'], def: r'$.data'),
      idPath: _asString(json['id_path'] ?? json['idPath'], def: 'id'),
      thumbPath: _asString(json['thumb_path'] ?? json['thumbPath'], def: 'thumb'),
      fullPath: _asString(json['full_path'] ?? json['fullPath'], def: 'full'),
      widthPath: (json['width_path'] ?? json['widthPath'])?.toString(),
      heightPath: (json['height_path'] ?? json['heightPath'])?.toString(),
      imagePrefix: (json['image_prefix'] ?? json['imagePrefix'])?.toString(),
      gradePath: (json['grade_path'] ?? json['gradePath'])?.toString(),

      keywordRequired: _asBool(json['keyword_required'] ?? json['keywordRequired'], def: false),
      defaultKeyword: (json['default_keyword'] ?? json['defaultKeyword'])?.toString(),

      // ✅ 两阶段模型字段
      detailUrl: (json['detail_url'] ?? json['detailUrl'])?.toString(),
      detailRootPath: (json['detail_root_path'] ?? json['detailRootPath'])?.toString(),

      uploaderPathCandidates: _parsePathCandidates(json['uploader_path'] ?? json['uploaderPath']),
      viewsPathCandidates: _parsePathCandidates(json['views_path'] ?? json['viewsPath']),
      favoritesPathCandidates: _parsePathCandidates(json['favorites_path'] ?? json['favoritesPath']),
      fileSizePathCandidates: _parsePathCandidates(json['file_size_path'] ?? json['fileSizePath']),
      createdAtPathCandidates: _parsePathCandidates(json['created_at_path'] ?? json['createdAtPath']),
      mimeTypePathCandidates: _parsePathCandidates(json['mime_type_path'] ?? json['mimeTypePath']),
      tagsPathCandidates: _parsePathCandidates(json['tags_path'] ?? json['tagsPath']),
    );
  }

  Map<String, dynamic> toJson() {
    dynamic encodeCandidates(List<String> c) => c.isEmpty ? null : c;

    return {
      'id': id,
      'name': name,
      'url': url,
      'headers': headers,
      'fixed_params': fixedParams,
      'api_key': apiKey,
      'api_key_name': apiKeyName,
      'api_key_in': apiKeyIn,
      'api_key_prefix': apiKeyPrefix,
      'filters': filters.map((e) => e.toJson()).toList(),

      'response_type': responseType,
      'param_page': paramPage,
      'param_keyword': paramKeyword,

      'page_mode': pageMode,
      'page_size': pageSize,
      'cursor_path': cursorPath,

      'list_path': listPath,
      'id_path': idPath,
      'thumb_path': thumbPath,
      'full_path': fullPath,
      'width_path': widthPath,
      'height_path': heightPath,
      'image_prefix': imagePrefix,
      'grade_path': gradePath,

      'keyword_required': keywordRequired,
      'default_keyword': defaultKeyword,

      // ✅ 两阶段模型字段
      'detail_url': detailUrl,
      'detail_root_path': detailRootPath,
      'uploader_path': encodeCandidates(uploaderPathCandidates),
      'views_path': encodeCandidates(viewsPathCandidates),
      'favorites_path': encodeCandidates(favoritesPathCandidates),
      'file_size_path': encodeCandidates(fileSizePathCandidates),
      'created_at_path': encodeCandidates(createdAtPathCandidates),
      'mime_type_path': encodeCandidates(mimeTypePathCandidates),
      'tags_path': encodeCandidates(tagsPathCandidates),
    };
  }
}

class SourceFilter {
  final String key;
  final String name;
  final String type; // 'single' | 'multi'
  final String encode; // 'join' | 'repeat' | 'merge'
  final String? separator;
  final List<SourceFilterOption> options;

  const SourceFilter({
    required this.key,
    required this.name,
    this.type = 'single',
    this.encode = 'join',
    this.separator,
    this.options = const [],
  });

  static String _asString(dynamic v, {String def = ''}) {
    final s = v?.toString() ?? '';
    return s.trim().isEmpty ? def : s;
  }

  static List<SourceFilterOption> _parseOptions(dynamic raw) {
    if (raw is! List) return const <SourceFilterOption>[];
    final out = <SourceFilterOption>[];
    for (final it in raw) {
      if (it is Map) {
        out.add(SourceFilterOption.fromJson(it.map((k, v) => MapEntry(k.toString(), v))));
      }
    }
    return out;
  }

  factory SourceFilter.fromJson(Map<String, dynamic> json) {
    return SourceFilter(
      key: _asString(json['key']),
      name: _asString(json['name'], def: _asString(json['key'])),
      type: _asString(json['type'], def: 'single'),
      encode: _asString(json['encode'], def: 'join'),
      separator: json['separator']?.toString(),
      options: _parseOptions(json['options']),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'type': type,
        'encode': encode,
        'separator': separator,
        'options': options.map((e) => e.toJson()).toList(),
      };
}

class SourceFilterOption {
  final String label;
  final String value;

  const SourceFilterOption({required this.label, required this.value});

  static String _asString(dynamic v, {String def = ''}) {
    final s = v?.toString() ?? '';
    return s.trim().isEmpty ? def : s;
  }

  factory SourceFilterOption.fromJson(Map<String, dynamic> json) {
    return SourceFilterOption(
      label: _asString(json['label'], def: _asString(json['value'])),
      value: _asString(json['value']),
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}