import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/user_data_repository.dart';
import 'repository_providers.dart';

/// One authoritative reactive state snapshot for the currently displayed
/// account. MainScreen is keyed by account id, so a session switch explicitly
/// reloads this provider before the data view is displayed.
final userDataProvider = StateNotifierProvider<UserDataNotifier, AsyncValue<UserData>>((ref) {
  return UserDataNotifier(ref.watch(userDataRepositoryProvider));
});

class UserDataNotifier extends StateNotifier<AsyncValue<UserData>> {
  UserDataNotifier(this._repository) : super(const AsyncLoading());

  final UserDataRepository _repository;
  String? _loadedUserId;
  int _generation = 0;

  String? get loadedUserId => _loadedUserId;

  Future<UserData> load(String userId, {ThemeMode defaultTheme = ThemeMode.system}) async {
    // Do not show a previous account's data while a new account is loading.
    final generation = ++_generation;
    _loadedUserId = null;
    state = const AsyncLoading();
    try {
      final data = await _repository.load(userId, defaultTheme: defaultTheme);
      if (generation == _generation) {
        _loadedUserId = userId;
        state = AsyncData(data);
      }
      return data;
    } catch (error, stackTrace) {
      if (generation == _generation) state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  /// Publishes an in-memory change synchronously so dependent widgets rebuild
  /// immediately; [persist] then writes that snapshot to local storage.
  void publish(String userId, UserData data) {
    if (_loadedUserId != userId) {
      throw StateError('Cannot update data for an account that is not loaded.');
    }
    state = AsyncData(_stateShell(data));
  }

  Future<void> persist(String userId, UserData data) async {
    if (_loadedUserId != userId) {
      throw StateError('Cannot save data for an account that is not loaded.');
    }
    await _repository.save(userId, data);
    // Do not let a save from a previous session replace the new account's state.
    if (_loadedUserId == userId) {
      state = AsyncData(_stateShell(data));
    }
  }

  /// Import/restore path: save first, then replace the live state, so a failed
  /// write never reports an import as successful.
  Future<void> replaceAndPersist(String userId, UserData data) async {
    if (_loadedUserId != userId) {
      throw StateError('Cannot replace data for an account that is not loaded.');
    }
    final generation = _generation;
    await _repository.save(userId, data);
    if (generation == _generation && _loadedUserId == userId) {
      state = AsyncData(_stateShell(data));
    }
  }

  // Publish a fresh wrapper while retaining the model/list references. The UI
  // uses mutable legacy model classes and undo closures retain list references;
  // a wrapper identity change is enough to notify Riverpod dependants without
  // breaking those existing references during this incremental refactor.
  UserData _stateShell(UserData data) => UserData(
        terms: data.terms,
        reminders: data.reminders,
        groups: data.groups,
        settings: data.settings,
        profile: data.profile,
      );

  Future<void> flush() => _repository.flush();
}
