import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'data_codec.dart';

class StorageException implements Exception {
  const StorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Saves each user's data under its own key (`gp_data_v1_<userId>`), so one
/// account can never read or overwrite another account's records.
class StorageService {
  StorageService(this._prefs);

  static const String _themeKey = 'gp_theme_mode_v1';

  final SharedPreferences _prefs;
  Future<void> _queue = Future<void>.value();

  String _key(String uid) => 'gp_data_v1_$uid';

  /// Loads a user's data. A brand-new user (nothing saved yet) gets EMPTY data
  /// (never sample data). A corrupted record throws and is left untouched.
  Future<UserData> load(
    String uid, {
    ThemeMode defaultTheme = ThemeMode.system,
  }) async {
    final raw = _prefs.getString(_key(uid));
    if (raw == null) return UserData.empty(themeMode: defaultTheme);
    try {
      // Goes through the codec so older schema versions are migrated and the
      // record is validated. The stored text is never modified here.
      return UserDataCodec.parseDecoded(jsonDecode(raw)).data;
    } catch (_) {
      throw const StorageException(
        'Your saved data could not be read. It has not been changed or deleted.',
      );
    }
  }

  /// Saves a snapshot of [data]. The snapshot is encoded immediately, and the
  /// writes run one after another so an older save can never land after a newer
  /// one. Throws [StorageException] if the write fails.
  Future<void> save(String uid, UserData data) {
    final encoded = jsonEncode(data.toJson());
    final result = _queue.then((_) async {
      final ok = await _prefs.setString(_key(uid), encoded);
      if (!ok) throw const StorageException('Saving failed.');
    });
    _queue = result.catchError((Object _) {});
    return result;
  }

  /// Completes once every queued save has finished.
  Future<void> flush() => _queue;

  // Device-level mirror of the theme so the welcome screen (shown while nobody
  // is signed in) uses the last chosen theme.
  ThemeMode get globalTheme =>
      AppSettings.parseThemeMode(_prefs.getString(_themeKey));

  Future<void> saveGlobalTheme(ThemeMode mode) async {
    await _prefs.setString(_themeKey, mode.name);
  }
}
