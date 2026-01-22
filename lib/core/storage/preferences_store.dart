// lib/core/storage/preferences_store.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A thin, centralized persistence layer over [SharedPreferences].
///
/// Architecture constraints:
/// - Non-core layers MUST NOT import SharedPreferences directly.
/// - Keys should live here (or within core managers/services), not in UI widgets.
///
/// Reliability goals:
/// - Never throw (fail closed): persistence failures must not crash UI flows.
/// - Cache SharedPreferences instance to avoid repeated async initialization.
class PreferencesStore {
  const PreferencesStore();

  static SharedPreferences? _cached;
  static Future<SharedPreferences> _prefs() async {
    final existing = _cached;
    if (existing != null) return existing;
    final created = await SharedPreferences.getInstance();
    _cached = created;
    return created;
  }

  // -------------------- generic primitives --------------------

  Future<String?> getString(String key) async {
    try {
      final prefs = await _prefs();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(key, value);
    } catch (_) {
      // swallow
    }
  }

  Future<List<String>?> getStringList(String key) async {
    try {
      final prefs = await _prefs();
      return prefs.getStringList(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> setStringList(String key, List<String> value) async {
    try {
      final prefs = await _prefs();
      await prefs.setStringList(key, value);
    } catch (_) {
      // swallow
    }
  }

  Future<void> remove(String key) async {
    try {
      final prefs = await _prefs();
      await prefs.remove(key);
    } catch (_) {
      // swallow
    }
  }

  // -------------------- filters --------------------

  String _filtersKey(String ruleId) => 'filter_prefs_$ruleId';

  Future<Map<String, dynamic>> loadFilters(String ruleId) async {
    try {
      final prefs = await _prefs();
      final jsonStr = (prefs.getString(_filtersKey(ruleId)) ?? '').trim();
      if (jsonStr.isEmpty) return <String, dynamic>{};

      final raw = jsonDecode(jsonStr);
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      // swallow
    }
    return <String, dynamic>{};
  }

  Future<void> saveFilters(String ruleId, Map<String, dynamic> filters) async {
    try {
      final prefs = await _prefs();
      if (filters.isEmpty) {
        await prefs.remove(_filtersKey(ruleId));
        return;
      }
      await prefs.setString(_filtersKey(ruleId), jsonEncode(filters));
    } catch (_) {
      // swallow
    }
  }

  // -------------------- pixiv cookie --------------------

  String _pixivCookieKey(String ruleId) => 'pixiv_cookie_$ruleId';

  Future<String?> loadPixivCookie(String ruleId) async {
    try {
      final prefs = await _prefs();
      final c = (prefs.getString(_pixivCookieKey(ruleId)) ?? '').trim();
      return c.isEmpty ? null : c;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePixivCookie(String ruleId, String? cookie) async {
    try {
      final prefs = await _prefs();
      final c = (cookie ?? '').trim();
      if (c.isEmpty) {
        await prefs.remove(_pixivCookieKey(ruleId));
      } else {
        await prefs.setString(_pixivCookieKey(ruleId), c);
      }
    } catch (_) {
      // swallow
    }
  }

  Future<void> clearPixivCookie(String ruleId) async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_pixivCookieKey(ruleId));
    } catch (_) {
      // swallow
    }
  }

  // -------------------- pixiv preferences --------------------

  static const String _kPixivPrefsKey = 'pixiv_preferences_v1';

  Future<Map<String, dynamic>?> loadPixivPrefsRaw() async {
    try {
      final prefs = await _prefs();
      final jsonStr = (prefs.getString(_kPixivPrefsKey) ?? '').trim();
      if (jsonStr.isEmpty) return null;

      final raw = jsonDecode(jsonStr);
      if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      // swallow
    }
    return null;
  }

  Future<void> savePixivPrefsRaw(Map<String, dynamic> map) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_kPixivPrefsKey, jsonEncode(map));
    } catch (_) {
      // swallow
    }
  }
}