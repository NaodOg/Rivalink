import 'package:flutter/material.dart';

import '../data/repositories/app_repository.dart';
import '../data/services/cache_service.dart';
import '../data/services/push_service.dart';
import '../data/services/analytics_service.dart';

class SessionController extends ChangeNotifier {
  final AppRepository _repo;
  SessionController(this._repo);

  bool loading = true;
  bool hasError = false;
  String? errorMessage;
  String? token;
  Map<String, dynamic>? user;

  /// Restore the stored session (local storage only, no network) so the first
  /// route can be chosen before the app renders.
  Future<void> hydrate() async {
    final session = await _repo.getSession();
    token = session?['token'] as String?;
    user = session?['user'] as Map<String, dynamic>?;
    CacheService.setUserScope(user?['id']?.toString());
    await CacheService.pruneStaleVersions();
  }

  Future<void> bootstrap() async {
    loading = true;
    hasError = false;
    errorMessage = null;
    notifyListeners();
    try {
      final session = await _repo.getSession();
      token = session?['token'] as String?;
      user = session?['user'] as Map<String, dynamic>?;
      CacheService.setUserScope(user?['id']?.toString());
      AnalyticsService.identify(user?['id'] as int?);
      if (token != null) {
        PushService.register(token!);
        final fresh = await _repo.getProfile(token!);
        if (fresh != null) {
          user = fresh;
          await _repo.saveSession(token!, fresh);
        }
      }
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    loading = true;
    hasError = false;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _repo.login(email, password);
      if (result['success'] == true) {
        token = result['token'] as String;
        user = Map<String, dynamic>.from(result['user'] as Map);
        CacheService.setUserScope(user?['id']?.toString());
        AnalyticsService.identify(user?['id'] as int?);
        await _repo.saveSession(token!, user!);
        PushService.register(token!);
        loading = false;
        notifyListeners();
        return true;
      }
      errorMessage = result['error']?.toString() ?? 'Login failed';
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
    }
    loading = false;
    notifyListeners();
    return false;
  }

  Future<bool> signup({
    required String name,
    required String phone,
    required String email,
    required String password,
    String location = '',
  }) async {
    loading = true;
    hasError = false;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _repo.signup(name: name, phone: phone, email: email, password: password, location: location);
      if (result['success'] == true) {
        token = result['token'] as String;
        user = Map<String, dynamic>.from(result['user'] as Map);
        CacheService.setUserScope(user?['id']?.toString());
        AnalyticsService.identify(user?['id'] as int?);
        await _repo.saveSession(token!, user!);
        PushService.register(token!);
        loading = false;
        notifyListeners();
        return true;
      }
      errorMessage = result['error']?.toString() ?? 'Signup failed';
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
    }
    loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    final oldToken = token;
    if (oldToken != null) {
      try {
        await _repo.logout(oldToken).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    await PushService.unregister();
    await _repo.clearSession();
    await CacheService.clearAllCache();
    AnalyticsService.identify(null);
    token = null;
    user = null;
    CacheService.setUserScope(null);
    notifyListeners();
  }

  Future<void> updateUser(Map<String, dynamic> newUser) async {
    user = newUser;
    if (token != null) {
      await _repo.saveSession(token!, newUser);
    }
    notifyListeners();
  }
}
