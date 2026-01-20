// lib/core/pixiv/pixiv_client.dart
import 'dart:convert';
import 'package:dio/dio.dart';

/// Pixiv Ajax API Client
///
/// 核心机制：
/// 1. 主要是伪装成浏览器访问 https://www.pixiv.net/ajax/...
/// 2. 图片加载(i.pximg.net)必须带 Referer: https://www.pixiv.net/
class PixivClient {
  final Dio _dio;
  String? _cookie;
  
  // 默认使用 PC 端 UA，兼容性最好。
  // 提示：如果要用 Touch API (/touch/ajax/...)，建议在请求时临时切换 UA，或者全局模拟手机
  String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final void Function(String msg)? _log;

  PixivClient({
    Dio? dio,
    String? cookie,
    void Function(String msg)? logger,
  })  : _dio = dio ?? Dio(),
        _cookie = cookie,
        _log = logger {
    
    // 基础配置
    _dio.options = BaseOptions(
      baseUrl: 'https://www.pixiv.net',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      // 允许 404 等状态码不抛错，便于手动处理业务逻辑
      validateStatus: (status) => status != null && status < 500, 
    );
    
    _refreshHeaders();
  }

  bool get hasCookie => (_cookie?.trim().isNotEmpty ?? false);

  /// 外部调用：更新配置（登录后、切换账号时）
  void updateConfig({String? cookie, String? userAgent}) {
    bool changed = false;
    if (cookie != null) {
      _cookie = cookie;
      changed = true;
    }
    if (userAgent != null && userAgent.isNotEmpty) {
      _userAgent = userAgent;
      changed = true;
    }
    if (changed) _refreshHeaders();
  }

  void _refreshHeaders() {
    _dio.options.headers = {
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/', // 关键：防盗链检查
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8', // 尽量让 P 站返回中文 tag
      if (hasCookie) 'Cookie': _cookie!,
    };
  }

  /// 图片下载/缓存专用 Headers
  Map<String, String> buildImageHeaders() {
    return {
      'User-Agent': _userAgent,
      'Referer': 'https://www.pixiv.net/',
      if (hasCookie) 'Cookie': _cookie!,
    };
  }

  // =========================================================
  // 核心 API 方法
  // =========================================================

  /// 检查登录状态
  Future<bool> checkLogin() async {
    if (!hasCookie) return false;

    try {
      // 这里的 header 会自动使用 _dio.options.headers
      final resp = await _dio.get('/ajax/user/self');
      
      if ((resp.statusCode ?? 0) >= 400) {
        _log?.call('CheckLogin: HTTP ${resp.statusCode}');
        return false;
      }

      final data = resp.data;
      if (data is! Map) return false;

      // 1. 尝试解析 Desktop 结构
      // {"body": {"userId": "123"}, "error": false}
      if (data['body'] is Map) {
        final uid = data['body']['userId']?.toString() ?? '';
        if (uid.isNotEmpty) {
          _log?.call('CheckLogin: Success (Desktop) UID=$uid');
          return true;
        }
      }

      // 2. 尝试解析 Mobile 结构 (Touch API)
      // {"userData": {"id": "123"}}
      if (data['userData'] is Map) {
        final uid = data['userData']['id']?.toString() ?? '';
        if (uid.isNotEmpty) {
          _log?.call('CheckLogin: Success (Mobile) UID=$uid');
          return true;
        }
      }
      
      _log?.call('CheckLogin: Unknown structure');
      return false;
    } catch (e) {
      _log?.call('CheckLogin Error: $e');
      return false;
    }
  }

  /// 搜索插画
  Future<List<PixivIllustBrief>> searchArtworks({
    required String word,
    int page = 1,
    String order = 'date_d', // date_d (新到旧) | popular_d (热门-需要会员)
    String mode = 'all',     // all | r18 | safe
    String sMode = 's_tag',  // s_tag (标签完全匹配) | s_tag_full (标签部分匹配)
  }) async {
    if (word.trim().isEmpty) return [];

    try {
      final resp = await _dio.get(
        '/ajax/search/artworks/${Uri.encodeComponent(word)}',
        queryParameters: {
          'word': word,
          'order': order,
          'mode': mode,
          's_mode': sMode,
          'p': page,
          'type': 'illust_and_ugoira', // 仅插画和动图，排除漫画
        },
      );

      if ((resp.statusCode ?? 0) >= 400) return [];

      final body = resp.data['body'];
      if (body == null || body is! Map) return [];

      // 注意：Key 可能是 illustManga 也可能是 illust
      final container = body['illustManga'] ?? body['illust'];
      if (container == null || container is! Map) return [];

      final list = container['data'];
      if (list is! List) return [];

      return list
          .map((e) => PixivIllustBrief.fromJson(e))
          .where((e) => e.id.isNotEmpty) // 过滤掉广告或无效数据
          .toList();

    } catch (e) {
      _log?.call('Search Error: $e');
      return [];
    }
  }

  /// 获取作品详情页的图片链接
  Future<List<PixivPageUrls>> getIllustPages(String illustId) async {
    if (illustId.isEmpty) return [];
    
    try {
      final resp = await _dio.get('/ajax/illust/$illustId/pages');
      
      if ((resp.statusCode ?? 0) >= 400) return [];
      
      final body = resp.data['body'];
      if (body is! List) return [];

      return body.map((e) => PixivPageUrls.fromJson(e)).toList();
    } catch (e) {
      _log?.call('GetPages Error: $e');
      return [];
    }
  }

  /// 获取指定用户的作品列表 (使用 Touch API)
  Future<List<PixivIllustBrief>> getUserArtworks({
    required String userId,
    int page = 1,
  }) async {
    if (userId.isEmpty) return [];

    try {
      // Touch API 通常返回分页更方便
      final resp = await _dio.get(
        '/touch/ajax/user/illusts',
        queryParameters: {
          'user_id': userId,
          'p': page,
        },
      );

      final data = resp.data;
      if (data is! Map) return [];
      
      // Touch API 结构: body -> illusts (List)
      final body = data['body'];
      if (body is! Map) return [];
      
      final list = body['illusts'];
      if (list is! List) return [];

      return list.map((e) => PixivIllustBrief.fromMap(e)).toList();

    } catch (e) {
      _log?.call('UserArtworks Error: $e');
      return [];
    }
  }
}

// =========================================================
// 数据模型 (Model)
// =========================================================

class PixivIllustBrief {
  final String id;
  final String title;
  final String thumbUrl; // 缩略图
  final int width;
  final int height;
  final int xRestrict; // 0: 全年龄, 1: R18, 2: R18G
  final List<String> tags; // 新增：方便展示 tag

  const PixivIllustBrief({
    required this.id,
    required this.title,
    required this.thumbUrl,
    required this.width,
    required this.height,
    required this.xRestrict,
    this.tags = const [],
  });

  /// 解析 Desktop Search API 的数据
  factory PixivIllustBrief.fromJson(dynamic json) {
    if (json is! Map) return _empty();
    
    // 广告位检测：有些 item 只有 adContainerUrl，没有 id
    if (json['id'] == null) return _empty();

    return PixivIllustBrief(
      id: _parseString(json['id']),
      title: _parseString(json['title']),
      thumbUrl: _parseString(json['url']),
      width: _parseInt(json['width']),
      height: _parseInt(json['height']),
      xRestrict: _parseInt(json['xRestrict']),
      tags: _parseTags(json['tags']),
    );
  }

  /// 解析 Touch/Mobile API 的数据 (字段风格不同，比如 snake_case)
  factory PixivIllustBrief.fromMap(dynamic json) {
     if (json is! Map) return _empty();
     
     return PixivIllustBrief(
      id: _parseString(json['id']),
      title: _parseString(json['title']),
      thumbUrl: _parseString(json['url']), // Touch API 通常也是 url
      width: _parseInt(json['width']),
      height: _parseInt(json['height']),
      xRestrict: _parseInt(json['x_restrict']), // 注意下划线
      tags: _parseTags(json['tags']),
    );
  }

  static PixivIllustBrief _empty() {
    return const PixivIllustBrief(
        id: '', title: '', thumbUrl: '', width: 0, height: 0, xRestrict: 0);
  }

  // --- 安全解析辅助函数 ---
  static String _parseString(dynamic v) => v?.toString() ?? '';
  
  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
  
  static List<String> _parseTags(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}

class PixivPageUrls {
  final String original;
  final String regular;
  final String small;
  final String thumbMini;

  const PixivPageUrls({
    required this.original,
    required this.regular,
    required this.small,
    required this.thumbMini,
  });

  factory PixivPageUrls.fromJson(dynamic json) {
    if (json is! Map) return _empty();
    final urls = json['urls'];
    if (urls is! Map) return _empty();

    return PixivPageUrls(
      original: urls['original']?.toString() ?? '',
      regular: urls['regular']?.toString() ?? '',
      small: urls['small']?.toString() ?? '',
      thumbMini: urls['thumb_mini']?.toString() ?? '',
    );
  }

  static PixivPageUrls _empty() {
    return const PixivPageUrls(original: '', regular: '', small: '', thumbMini: '');
  }
}
