// lib/core/engine/rule_engine.dart
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:json_path/json_path.dart';

import '../models/source_rule.dart';
import '../models/uni_wallpaper.dart';
import '../storage/preferences_store.dart';
import '../utils/prism_logger.dart';
import 'base_image_source.dart';

class RuleEngine implements BaseImageSource {
  RuleEngine({Dio? dio, PrismLogger? logger})
      : _dio = dio ?? Dio(),
        _logger = logger;

  final Dio _dio;
  final PrismLogger? _logger;

  final Map<String, dynamic> _cursorCache = {};

  // ==================== BaseImageSource ====================

  @override
  bool supports(SourceRule rule) => true;

  @override
  Future<void> restoreSession({
    required PreferencesStore prefs,
    required SourceRule rule,
  }) async {
    // 通用 JSON 规则通常无需会话恢复
  }

  @override
  Future<bool> checkLoginStatus(SourceRule rule) async => true;

  // ============================================================
  // ✅ FIX #1：统一 URL 解析
  // - 绝对 URL（http/https）必须原样返回
  // - 仅相对路径才拼 imagePrefix
  // ============================================================
  String _resolveImageUrl(String? raw, SourceRule rule) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return s;

    final prefix = rule.imagePrefix;
    if (prefix == null || prefix.trim().isEmpty) return s;

    return prefix + s;
  }

  @override
  Future<List<UniWallpaper>> fetch(
    SourceRule rule, {
    int page = 1,
    String? query,
    Map<String, dynamic>? filterParams,
  }) async {
    final Map<String, dynamic> params = {};
    if (rule.fixedParams != null) params.addAll(rule.fixedParams!);

    final Map<String, String> reqHeaders = {
      ..._defaultUA(),
      ...?rule.headers,
    };

    // apiKey
    final apiKey = rule.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      final keyName = (rule.apiKeyName == null || rule.apiKeyName!.isEmpty) ? 'apikey' : rule.apiKeyName!;
      if (rule.apiKeyIn == 'header') {
        reqHeaders[keyName] = '${rule.apiKeyPrefix}$apiKey';
      } else {
        _putParam(params, keyName, apiKey);
      }
    }

    // merge 多选参数
    final Map<String, List<String>> mergeMulti = {};
    if (filterParams != null) {
      filterParams.forEach((key, value) {
        if (value is List) {
          SourceFilter? filterRule;
          for (final f in rule.filters) {
            if (f.key == key) {
              filterRule = f;
              break;
            }
          }

          final encode = (filterRule?.encode ?? 'join').toLowerCase();
          final cleaned = value
              .map((e) => e?.toString() ?? '')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (cleaned.isEmpty) return;

          if (encode == 'merge') {
            mergeMulti[key] = cleaned;
          } else if (encode == 'repeat') {
            params[key] = cleaned;
          } else {
            final separator = filterRule?.separator ?? ',';
            final joined = cleaned.join(separator);
            if (joined.trim().isNotEmpty) params[key] = joined;
          }
        } else {
          _putParam(params, key, value);
        }
      });
    }

    // keyword 策略
    String? finalQuery = query;
    if ((finalQuery == null || finalQuery.trim().isEmpty) &&
        rule.defaultKeyword != null &&
        rule.defaultKeyword!.trim().isNotEmpty) {
      finalQuery = rule.defaultKeyword;
    }

    if (rule.keywordRequired && (finalQuery == null || finalQuery.trim().isEmpty)) {
      throw ArgumentError('keyword_required');
    }

    if (finalQuery != null && finalQuery.trim().isNotEmpty) {
      if (rule.paramKeyword.isNotEmpty) {
        _putParam(params, rule.paramKeyword, finalQuery.trim());
      }
    }

    final String requestUrl = _buildRequestUrl(rule, finalQuery);

    // 分页策略
    if (rule.responseType != 'random') {
      if (rule.paramPage.isNotEmpty) {
        if (rule.pageMode == 'offset') {
          final size = (rule.pageSize > 0) ? rule.pageSize : _guessPageSize(rule, params);
          final offset = (page - 1) * size;
          params[rule.paramPage] = offset;
        } else if (rule.pageMode == 'cursor') {
          final ck = _cursorKey(rule, finalQuery, filterParams);
          if (page <= 1) {
            if (_cursorCache.containsKey(ck)) {
              _cursorCache.remove(ck);
              _logger?.log('CURSOR ${rule.id} cleared (refresh)');
            }
          } else {
            final cursor = _cursorCache[ck];
            if (cursor != null) {
              params[rule.paramPage] = cursor;
            } else {
              _logger?.debug('CURSOR ${rule.id} missing cache (page=$page)');
            }
          }
        } else {
          params[rule.paramPage] = page;
        }
      }
    }

    try {
      if (rule.responseType == 'random') {
        return await _fetchRandomMode(rule, requestUrl, params, reqHeaders);
      } else {
        if (mergeMulti.isEmpty) {
          return await _fetchJsonMode(
            rule,
            requestUrl,
            params,
            reqHeaders,
            finalQuery: finalQuery,
            filterParams: filterParams,
          );
        }
        return await _fetchJsonModeMerge(rule, requestUrl, params, reqHeaders, mergeMulti);
      }
    } catch (e) {
      _logger?.log('Engine Error: $e');
      rethrow;
    }
  }

  // ============================================================
  // ✅ 新增：详情补全（供 WallpaperService / DetailPage 调用）
  // ============================================================
  Future<UniWallpaper> fetchDetail(
    SourceRule rule,
    UniWallpaper base, {
    Map<String, String>? headers,
  }) async {
    final detailUrlTpl = rule.detailUrl?.trim() ?? '';
    if (detailUrlTpl.isEmpty) return base;

    final url = detailUrlTpl.replaceAll('{id}', Uri.encodeComponent(base.id));
    final reqHeaders = <String, String>{
      ..._defaultUA(),
      ...?rule.headers,
      ...?headers,
    };

    try {
      _logReq(rule, url, const {}, reqHeaders);

      final response = await _dio.get(
        url,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      _logResp(rule, response.statusCode, response.realUri.toString(), response.data);

      final sc = response.statusCode ?? 0;
      if (sc >= 400) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'HTTP $sc',
        );
      }

      final root = _selectRoot(rule.detailRootPath, response.data);
      return _applyMetaFromObject(rule, base, root);
    } on DioException catch (e) {
      _logErr(rule, e.response?.statusCode, e.requestOptions.uri.toString(), e, e.response?.data);
      rethrow;
    } catch (e) {
      _logErr(rule, null, url, e, null);
      rethrow;
    }
  }

  // ==================== Stage 2：归一化 & 赋值 ====================

  UniWallpaper _applyMetaFromObject(SourceRule rule, UniWallpaper base, dynamic obj) {
    // uploader
    final uploader = _normalizeText(_pickFirstString(rule.uploaderPathCandidates, obj));
    // views/favs/size/date/mime
    final views = _normalizeText(_pickFirstString(rule.viewsPathCandidates, obj));
    final favs = _normalizeText(_pickFirstString(rule.favoritesPathCandidates, obj));
    final size = _normalizeText(_pickFirstString(rule.fileSizePathCandidates, obj));
    final createdAt = _normalizeText(_pickFirstString(rule.createdAtPathCandidates, obj));
    final mime = _normalizeText(_pickFirstString(rule.mimeTypePathCandidates, obj));

    final tags = _normalizeTags(_pickFirstDynamic(rule.tagsPathCandidates, obj));

    // ✅ 兜底策略：不覆盖已有的“更好值”
    String keepBetter(String oldV, String newV, {String bad = ''}) {
      final o = oldV.trim();
      final n = newV.trim();
      if (n.isEmpty) return o;
      if (o.isEmpty || o == bad) return n;
      return o;
    }

    final mergedUploader = keepBetter(base.uploader, uploader, bad: 'Unknown User');
    final mergedViews = keepBetter(base.views, views);
    final mergedFavs = keepBetter(base.favorites, favs);
    final mergedSize = keepBetter(base.fileSize, size);
    final mergedCreatedAt = keepBetter(base.createdAt, createdAt);
    final mergedMime = keepBetter(base.mimeType, mime);

    final mergedTags = (tags.isNotEmpty) ? tags : base.tags;

    return base.copyWith(
      uploader: mergedUploader,
      views: mergedViews,
      favorites: mergedFavs,
      fileSize: mergedSize,
      createdAt: mergedCreatedAt,
      mimeType: mergedMime,
      tags: mergedTags,
    );
  }

  String _normalizeText(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return '';
    final low = v.toLowerCase();
    if (low == 'null' || low == 'undefined' || low == 'nan') return '';
    return v;
  }

  List<String> _normalizeTags(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      final out = raw
          .map((e) => (e?.toString() ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      return out;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return const [];
    final parts = s
        .split(RegExp(r'[,;\| ]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return parts;
  }

  String? _pickFirstString(List<String> candidates, dynamic source) {
    final v = _pickFirstDynamic(candidates, source);
    if (v == null) return null;
    return v.toString();
  }

  dynamic _pickFirstDynamic(List<String> candidates, dynamic source) {
    if (candidates.isEmpty) return null;
    for (final p in candidates) {
      final v = _getValue<dynamic>(p, source);
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      return v;
    }
    return null;
  }

  dynamic _selectRoot(String? rootPath, dynamic json) {
    final p = (rootPath ?? '').trim();
    if (p.isEmpty || p == '.' || p == r'$') return json;
    return _getValue<dynamic>(p, json) ?? json;
  }

  // ==================== 原有逻辑（保持） ====================

  dynamic _readDotPath(dynamic source, String path) {
    if (path.isEmpty) return null;
    if (path == '.') return source;
    dynamic cur = source;
    for (final part in path.split('.')) {
      if (cur == null) return null;
      if (cur is Map) {
        cur = cur[part];
        continue;
      }
      if (cur is List) {
        final idx = int.tryParse(part);
        if (idx == null || idx < 0 || idx >= cur.length) return null;
        cur = cur[idx];
        continue;
      }
      return null;
    }
    return cur;
  }

  T? _getValue<T>(String path, dynamic source) {
    try {
      if (path.isEmpty) return null;
      if (path == '.') return source as T;
      final p = path.trimLeft();
      if (p.startsWith(r'$')) {
        final jp = JsonPath(path);
        return jp.read(source).firstOrNull?.value as T?;
      }
      final v = _readDotPath(source, path);
      return v as T?;
    } catch (_) {
      return null;
    }
  }

  num _toNum(dynamic x) {
    if (x is num) return x;
    return num.tryParse(x?.toString() ?? '') ?? 0;
  }

  Map<String, String> _defaultUA() => const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };

  String _mask(String v) {
    if (v.length <= 16) return '***';
    return '${v.substring(0, 12)}***';
  }

  Map<String, String> _maskHeaders(Map<String, String> headers) {
    final m = Map<String, dynamic>.from(headers);
    String safeVal(dynamic v) => v?.toString() ?? '';
    if (m.containsKey('Authorization')) m['Authorization'] = _mask(safeVal(m['Authorization']));
    if (m.containsKey('apikey')) m['apikey'] = _mask(safeVal(m['apikey']));
    if (m.containsKey('Api-Key')) m['Api-Key'] = _mask(safeVal(m['Api-Key']));
    if (m.containsKey('X-Api-Key')) m['X-Api-Key'] = _mask(safeVal(m['X-Api-Key']));
    if (m.containsKey('Cookie')) m['Cookie'] = '***';
    return m.map((k, v) => MapEntry(k, safeVal(v)));
  }

  void _logReq(SourceRule rule, String url, Map<String, dynamic> params, Map<String, String> headers) {
    _logger?.log('REQ ${rule.id} GET $url');
    _logger?.debug('    params=$params');
    _logger?.debug('    headers=${_maskHeaders(headers)}');
  }

  void _logResp(SourceRule rule, int? status, String realUrl, dynamic data) {
    _logger?.log('RESP ${rule.id} status=${status ?? 'N/A'} url=$realUrl');
    final s = (data == null) ? '' : data.toString();
    if (s.isNotEmpty) {
      _logger?.debug('    body=${s.length > 400 ? '${s.substring(0, 400)}...' : s}');
    }
  }

  void _logErr(SourceRule rule, int? status, String realUrl, Object e, dynamic data) {
    _logger?.log('ERR ${rule.id} status=${status ?? 'N/A'} url=$realUrl');
    _logger?.log('    err=$e');
    final s = (data == null) ? '' : data.toString();
    if (s.isNotEmpty) {
      _logger?.debug('    body=${s.length > 400 ? '${s.substring(0, 400)}...' : s}');
    }
  }

  String _cursorKey(SourceRule r, String? q, Map<String, dynamic>? f) {
    return '${r.id}|${q ?? ''}|${jsonEncode(f ?? {})}';
  }

  int _guessPageSize(SourceRule rule, Map<String, dynamic> params) {
    for (final k in ['per_page', 'limit', 'rows', 'count', 'page_size']) {
      final v = params[k];
      if (v is num && v > 0) return v.toInt();
      final vi = int.tryParse(v?.toString() ?? '');
      if (vi != null && vi > 0) return vi;
    }
    return 20;
  }

  String _stableId(SourceRule rule, dynamic item, String thumb, String full) {
    try {
      final raw = _getValue(rule.idPath, item);
      final s = raw?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    } catch (_) {}
    final f = full.trim();
    if (f.isNotEmpty) return f;
    final t = thumb.trim();
    if (t.isNotEmpty) return t;
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void _putParam(Map<String, dynamic> params, String key, dynamic value) {
    if (value == null) return;
    if (value is String) {
      if (value.trim().isEmpty) return;
      params[key] = value;
      return;
    }
    if (value is List) {
      final cleaned = value
          .map((e) => e?.toString() ?? '')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (cleaned.isEmpty) return;
      params[key] = cleaned;
      return;
    }
    params[key] = value;
  }

  String _buildRequestUrl(SourceRule rule, String? finalQuery) {
    final u = rule.url;
    final hasTpl = u.contains('{keyword}') || u.contains('{word}') || u.contains('{q}');
    if (!hasTpl) return u;
    final kw = (finalQuery ?? '').trim();
    if (kw.isEmpty) {
      throw Exception('该图源需要关键词：keyword 为空（url 含 {keyword}/{word}/{q}）');
    }
    final enc = Uri.encodeComponent(kw);
    return u.replaceAll('{keyword}', enc).replaceAll('{word}', enc).replaceAll('{q}', enc);
  }

  Future<List<UniWallpaper>> _fetchRandomMode(
    SourceRule rule,
    String requestUrl,
    Map<String, dynamic> params,
    Map<String, String> headers,
  ) async {
    const int batchSize = 6;
    const int delayMs = 300;
    _logReq(rule, requestUrl, params, headers);

    final futures = List.generate(batchSize, (index) async {
      await Future.delayed(Duration(milliseconds: index * delayMs));
      try {
        final requestParams = Map<String, dynamic>.from(params);
        requestParams['_t'] = DateTime.now().millisecondsSinceEpoch + index;
        requestParams['_r'] = Random().nextInt(10000);
        String? finalUrl;
        try {
          final response = await _dio.head(
            requestUrl,
            queryParameters: requestParams,
            options: Options(
              headers: headers,
              followRedirects: true,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              validateStatus: (status) => status != null && status < 400,
            ),
          );
          finalUrl = response.realUri.toString();
        } catch (_) {
          try {
            final response = await _dio.get(
              requestUrl,
              queryParameters: requestParams,
              options: Options(
                headers: headers,
                followRedirects: true,
                responseType: ResponseType.stream,
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
                validateStatus: (s) => s != null && s < 500,
              ),
            );
            finalUrl = response.realUri.toString();
            (response.data as ResponseBody).close();
          } catch (_) {
            return null;
          }
        }
        if (finalUrl == null) return null;
        final uri = Uri.parse(finalUrl);
        if (uri.queryParameters.containsKey('_t') || uri.queryParameters.containsKey('_r')) {
          final newQueryParams = Map<String, String>.from(uri.queryParameters);
          newQueryParams.remove('_t');
          newQueryParams.remove('_r');
          finalUrl = uri.replace(queryParameters: newQueryParams).toString();
        }
        return finalUrl;
      } catch (_) {
        return null;
      }
    });

    final results = await Future.wait(futures);
    final List<UniWallpaper> wallpapers = [];
    for (final url in results) {
      if (url != null && url.startsWith('http')) {
        if (!wallpapers.any((w) => w.fullUrl == url)) {
          wallpapers.add(UniWallpaper(
            id: url,
            sourceId: rule.id,
            thumbUrl: url,
            fullUrl: url,
            width: 0,
            height: 0,
          ));
        }
      }
    }
    _logger?.log('RESP ${rule.id} random_count=${wallpapers.length}');
    return wallpapers;
  }

  List<UniWallpaper> _parseJsonToWallpapers(SourceRule rule, dynamic jsonMap) {
    final listPath = JsonPath(rule.listPath);
    final match = listPath.read(jsonMap).firstOrNull;
    if (match == null || match.value is! List) return [];
    final List list = match.value as List;
    final out = <UniWallpaper>[];

    for (final item in list) {
      // ============================================================
      // ✅ FIX #2：这里改为“统一 URL 解析”，不再用旧的 imagePrefix 拼接逻辑
      // ============================================================
      final rawThumb = _getValue<String>(rule.thumbPath, item);
      final rawFull = _getValue<String>(rule.fullPath, item);

      String thumb = _resolveImageUrl(rawThumb, rule);
      String full = _resolveImageUrl(rawFull ?? rawThumb, rule);

      final id = _stableId(rule, item, thumb, full);
      if (thumb.trim().isEmpty && full.trim().isEmpty) continue;

      final width = _toNum(_getValue(rule.widthPath ?? '', item)).toDouble();
      final height = _toNum(_getValue(rule.heightPath ?? '', item)).toDouble();
      final grade = _getValue<String>(rule.gradePath ?? '', item);

      // ✅ Stage 1+2：在列表解析阶段就尽量补齐元数据（通配候选路径）
      final base = UniWallpaper(
        id: id,
        sourceId: rule.id,
        thumbUrl: thumb,
        fullUrl: full,
        width: width,
        height: height,
        grade: grade,
      );

      final withMeta = _applyMetaFromObject(rule, base, item);
      out.add(withMeta);
    }

    return out;
  }

  Future<List<UniWallpaper>> _fetchJsonMode(
    SourceRule rule,
    String requestUrl,
    Map<String, dynamic> params,
    Map<String, String> headers, {
    required String? finalQuery,
    required Map<String, dynamic>? filterParams,
  }) async {
    _logReq(rule, requestUrl, params, headers);

    try {
      final response = await _dio.get(
        requestUrl,
        queryParameters: params,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      _logResp(rule, response.statusCode, response.realUri.toString(), response.data);

      final sc = response.statusCode ?? 0;
      if (sc >= 400) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'HTTP $sc',
        );
      }

      if (rule.pageMode == 'cursor' && rule.cursorPath != null && rule.cursorPath!.trim().isNotEmpty) {
        final nextCursor = _getValue(rule.cursorPath!, response.data);
        if (nextCursor != null) {
          final ck = _cursorKey(rule, finalQuery, filterParams);
          _cursorCache[ck] = nextCursor;
          _logger?.log('CURSOR ${rule.id} set=$nextCursor');
        } else {
          _logger?.debug('CURSOR ${rule.id} missing (cursor_path=${rule.cursorPath})');
        }
      }

      return _parseJsonToWallpapers(rule, response.data);
    } on DioException catch (e) {
      _logErr(rule, e.response?.statusCode, e.requestOptions.uri.toString(), e, e.response?.data);
      rethrow;
    } catch (e) {
      _logErr(rule, null, requestUrl, e, null);
      rethrow;
    }
  }

  Future<List<UniWallpaper>> _fetchJsonModeMerge(
    SourceRule rule,
    String requestUrl,
    Map<String, dynamic> baseParams,
    Map<String, String> headers,
    Map<String, List<String>> mergeMulti,
  ) async {
    List<Map<String, dynamic>> paramSets = [Map<String, dynamic>.from(baseParams)];
    mergeMulti.forEach((key, values) {
      final List<Map<String, dynamic>> next = [];
      for (final ps in paramSets) {
        for (final v in values) {
          final m = Map<String, dynamic>.from(ps);
          m[key] = v;
          next.add(m);
        }
      }
      paramSets = next;
    });

    _logger?.log('MERGE ${rule.id} requests=${paramSets.length} keys=${mergeMulti.keys.toList()}');
    final List<UniWallpaper> merged = [];
    final Set<String> seen = {};

    for (final ps in paramSets) {
      _logReq(rule, requestUrl, ps, headers);
      try {
        final resp = await _dio.get(
          requestUrl,
          queryParameters: ps,
          options: Options(
            headers: headers,
            responseType: ResponseType.json,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            validateStatus: (s) => s != null && s < 500,
          ),
        );

        _logResp(rule, resp.statusCode, resp.realUri.toString(), resp.data);

        final sc = resp.statusCode ?? 0;
        if (sc >= 400) {
          throw DioException(
            requestOptions: resp.requestOptions,
            response: resp,
            type: DioExceptionType.badResponse,
            error: 'HTTP $sc',
          );
        }

        final items = _parseJsonToWallpapers(rule, resp.data);
        for (final it in items) {
          if (seen.add(it.id)) merged.add(it);
        }
      } on DioException catch (e) {
        _logErr(rule, e.response?.statusCode, e.requestOptions.uri.toString(), e, e.response?.data);
        rethrow;
      } catch (e) {
        _logErr(rule, null, requestUrl, e, null);
        rethrow;
      }
    }

    _logger?.log('MERGE ${rule.id} merged=${merged.length}');
    return merged;
  }
}