import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'services/storage_service.dart';

/// App-level state: who is signed in and which theme is active.
class AppController extends ChangeNotifier {
  AppController(SharedPreferences prefs)
    : auth = AuthService(prefs),
      storage = StorageService(prefs);

  final AuthService auth;
  final StorageService storage;

  AppUser? user;
  ThemeMode themeMode = ThemeMode.system;

  /// Restores the theme and the signed-in session (if any) on launch.
  void init() {
    themeMode = storage.globalTheme;
    user = auth.restoreSession();
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    user = await auth.signUp(name: name, email: email, password: password);
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    user = await auth.signIn(email: email, password: password);
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String email,
  }) async {
    final current = user;
    if (current == null) throw const AuthException('Please sign in again.');
    user = await auth.updateProfile(userId: current.id, name: name, email: email);
    notifyListeners();
  }

  Future<void> signOut() async {
    await auth.signOut();
    user = null;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    await storage.saveGlobalTheme(mode);
  }
}
