import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const int _defaultCacheMinutes = 5;
  static String _scope = 'anon';

  /// Namespace all cache keys to the active user so data never leaks between
  /// accounts on a shared device. Call after login/signup/logout/bootstrap.
  static void setUserScope(String? userId) {
    _scope = userId == null ? 'anon' : 'u$userId';
  }

  static String _keyFor(String key) {
    return key.startsWith('cache_') ? '${key}_$_scope' : key;
  }

  static Future<void> setCachedData(String key, dynamic data, {int? cacheMinutes}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'duration': (cacheMinutes ?? _defaultCacheMinutes) * 60 * 1000,
      };
      await prefs.setString(_keyFor(key), json.encode(cacheData));
    } catch (e) {
      debugPrint('Cache set error: $e');
    }
  }

  static Future<dynamic> getCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_keyFor(key));
      if (cached == null) return null;

      final cacheData = json.decode(cached);
      final timestamp = cacheData['timestamp'] as int;
      final duration = cacheData['duration'] as int;

      if (DateTime.now().millisecondsSinceEpoch - timestamp > duration) {
        await prefs.remove(_keyFor(key));
        return null;
      }

      return cacheData['data'];
    } catch (e) {
      debugPrint('Cache get error: $e');
      return null;
    }
  }

  static Future<void> removeCachedData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(key));
    } catch (e) {
      debugPrint('Cache remove error: $e');
    }
  }

  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('cache_')).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Cache clear error: $e');
    }
  }

  static Future<void> invalidateTeams() async {
    await removeCachedData('${teamsKey}_my');
    await removeCachedData('${teamsKey}_seeking');
  }

  static Future<void> invalidateMatches() async {
    await removeCachedData(matchesKey);
  }

  static Future<void> invalidateLeagues() async {
    await removeCachedData('${leaguesKey}_all');
  }

  static Future<void> invalidateRecommendations() async {
    await removeCachedData(recommendationsKey);
  }

  static const String teamsKey = 'cache_teams';
  static const String matchesKey = 'cache_matches';
  static const String leaguesKey = 'cache_leagues';
  static const String venuesKey = 'cache_venues';
  static const String recommendationsKey = 'cache_recommendations';
}
