// lib/core/storage/preferences_store.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A thin, centralized persistence layer over [SharedPreferences].
///
/// UI layer MUST NOT depend on raw keys; use this store via [WallpaperService]/[SourceManager].
class PreferencesStore {
  const PreferencesStore();

  // -------------------- filters --------------------
  String _filtersKey(String ruleId) => 'filter_prefs_$ruleId';

  Future<Map<String, dynamic>> loadFilters(String ruleId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = (prefs.getString(_filtersKey(ruleId)) ?? '').trim();
    if (jsonStr.isEmpty) return <String, dynamic>{};

    try {
      final raw = jsonDecode(jsonStr);
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> saveFilters(String ruleId, Map<String, dynamic> filters) async {
    final prefs = await SharedPreferences.getInstance();
    if (filters.isEmpty) {
      await prefs.remove(_filtersKey(ruleId));
      return;
    }
    await prefs.setString(_filtersKey(ruleId), jsonEncode(filters));
  }

  // -------------------- pixiv cookie --------------------
  String _pixivCookieKey(String ruleId) => 'pixiv_cookie_$ruleId';

  Future<String?> loadPixivCookie(String ruleId) async {
    final prefs = await SharedPreferences.getInstance();
    final c = (prefs.getString(_pixivCookieKey(ruleId)) ?? '').trim();
    return c.isEmpty ? null : c;
  }

  Future<void> savePixivCookie(String ruleId, String? cookie) async {
    final prefs = await SharedPreferences.getInstance();
    final c = (cookie ?? '').trim();
    if (c.isEmpty) {
      await prefs.remove(_pixivCookieKey(ruleId));
    } else {
      await prefs.setString(_pixivCookieKey(ruleId), c);
    }
  }

  // -------------------- pixiv preferences --------------------
  static const String _kPixivPrefsKey = 'pixiv_preferences_v1';

  Future<Map<String, dynamic>?> loadPixivPrefsRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = (prefs.getString(_kPixivPrefsKey) ?? '').trim();
    if (jsonStr.isEmpty) return null;

    try {
      final raw = jsonDecode(jsonStr);
      if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    return null;
  }

  Future<void> savePixivPrefsRaw(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPixivPrefsKey, jsonEncode(map));
  }
}
