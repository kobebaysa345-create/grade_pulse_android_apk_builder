import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/storage_service.dart';

/// Storage boundary for one user's editable application data.
///
/// UI code depends on this interface rather than SharedPreferences directly.
abstract interface class UserDataRepository {
  Future<UserData> load(String userId, {ThemeMode defaultTheme = ThemeMode.system});
  Future<void> save(String userId, UserData data);
  Future<void> flush();
}

/// Local implementation backed by Grade Pulse's versioned, per-user storage.
/// Existing serialized records and migration logic remain in [StorageService].
class LocalUserDataRepository implements UserDataRepository {
  const LocalUserDataRepository(this._storage);

  final StorageService _storage;

  @override
  Future<UserData> load(String userId, {ThemeMode defaultTheme = ThemeMode.system}) =>
      _storage.load(userId, defaultTheme: defaultTheme);

  @override
  Future<void> save(String userId, UserData data) => _storage.save(userId, data);

  @override
  Future<void> flush() => _storage.flush();
}
