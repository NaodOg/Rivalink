import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const int _defaultCacheMinutes = 5;
  static const int _version = 1;
  static String _scope = 'anon';
  static bool _pruned = false;

  /// Namespace all cache keys to the active user so data never leaks between
  /// accounts on a shared device. Call after login/signup/logout/bootstrap.
  static void setUserScope(String? userId) {
    _scope = userId == null ? 'anon' : 'u$userId';
  }

  static String _keyFor(String key) => '${key}_v${_version}_$_scope';

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

  /// Read a cached value. Expired entries are removed unless [allowStale] is
  /// set, which is used to fall back to the last-known data when offline.
  static Future<dynamic> getCachedData(String key, {bool allowStale = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_keyFor(key));
      if (cached == null) return null;

      final cacheData = json.decode(cached);
      final timestamp = cacheData['timestamp'] as int;
      final duration = cacheData['duration'] as int;
      final expired =
          DateTime.now().millisecondsSinceEpoch - timestamp > duration;

      if (expired && !allowStale) {
        await prefs.remove(_keyFor(key));
        return null;
      }

      return cacheData['data'];
    } catch (e) {
      debugPrint('Cache get error: $e');
      return null;
    }
  }

  /// Cache-first fetch shared by every service:
  /// 1. return fresh cache unless [forceRefresh],
  /// 2. otherwise fetch and store,
  /// 3. on network failure fall back to stale cache, then rethrow.
  static Future<T> cachedFetch<T>({
    required String key,
    required Future<T> Function() fetch,
    required int cacheMinutes,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await getCachedData(key);
      if (cached is T) return cached;
    }
    try {
      final data = await fetch();
      await setCachedData(key, data, cacheMinutes: cacheMinutes);
      return data;
    } catch (_) {
      final stale = await getCachedData(key, allowStale: true);
      if (stale is T) return stale;
      rethrow;
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

  /// Drop entries written by older cache layouts. Runs once per process.
  static Future<void> pruneStaleVersions() async {
    if (_pruned) return;
    _pruned = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith('cache_') && !k.contains('_v${_version}_'))
          .toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Cache prune error: $e');
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

  static Future<void> invalidateVenues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(venuesKey)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Cache invalidate venues error: $e');
    }
  }

  static Future<void> invalidateRecommendations() async {
    await removeCachedData(recommendationsKey);
  }

  static Future<void> invalidateUserStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((k) => k.startsWith('cache_user_stats')).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Cache invalidate user stats error: $e');
    }
  }

  static const String teamsKey = 'cache_teams';
  static const String matchesKey = 'cache_matches';
  static const String leaguesKey = 'cache_leagues';
  static const String venuesKey = 'cache_venues';
  static const String recommendationsKey = 'cache_recommendations';
}
