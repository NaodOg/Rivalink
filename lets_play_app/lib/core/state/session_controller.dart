import 'package:flutter/material.dart';

import '../data/repositories/app_repository.dart';

class SessionController extends ChangeNotifier {
  final AppRepository _repo;
  SessionController(this._repo);

  bool loading = true;
  String? token;
  Map<String, dynamic>? user;

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();
    final session = await _repo.getSession();
    token = session?['token'] as String?;
    user = session?['user'] as Map<String, dynamic>?;
    loading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    loading = true;
    notifyListeners();
    final result = await _repo.login(email, password);
    if (result['success'] == true) {
      token = result['token'] as String;
      user = Map<String, dynamic>.from(result['user'] as Map);
      await _repo.saveSession(token!, user!);
      loading = false;
      notifyListeners();
      return true;
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
    notifyListeners();
    final result = await _repo.signup(name: name, phone: phone, email: email, password: password, location: location);
    if (result['success'] == true) {
      token = result['token'] as String;
      user = Map<String, dynamic>.from(result['user'] as Map);
      await _repo.saveSession(token!, user!);
      loading = false;
      notifyListeners();
      return true;
    }
    loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await _repo.clearSession();
    token = null;
    user = null;
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
