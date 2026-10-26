import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/providers/repository_providers.dart';
import 'package:grade_pulse/providers/user_data_provider.dart';
import 'package:grade_pulse/repositories/user_data_repository.dart';

class _MemoryUserDataRepository implements UserDataRepository {
  final Map<String, UserData> records = {};
  int saves = 0;
  bool failNextSave = false;

  @override
  Future<UserData> load(String userId, {ThemeMode defaultTheme = ThemeMode.system}) async {
    final saved = records[userId];
    if (saved == null) return UserData.empty(themeMode: defaultTheme);
    return UserData.fromJson(saved.toJson());
  }

  @override
  Future<void> save(String userId, UserData data) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('simulated save failure');
    }
    records[userId] = UserData.fromJson(data.toJson());
    saves++;
  }

  @override
  Future<void> flush() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads per-user data and publishes state changes', () async {
    final repository = _MemoryUserDataRepository();
    final container = ProviderContainer(overrides: [
      userDataRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(userDataProvider.notifier);
    final loaded = await notifier.load('alice');
    expect(loaded.terms, isEmpty);

    final first = UserData(
      terms: [AcademicTerm(name: 'Term 1', courses: <Course>[])],
      reminders: <Reminder>[],
      groups: <StudyGroup>[],
      settings: AppSettings(),
    );
    await notifier.replaceAndPersist('alice', first);
    expect(container.read(userDataProvider).valueOrNull?.terms.single.name, 'Term 1');
    expect(repository.saves, 1);

    final before = container.read(userDataProvider);
    notifier.publish('alice', first);
    final after = container.read(userDataProvider);
    expect(identical(before, after), isFalse);
  });

  test('does not allow saving data for a different active account', () async {
    final repository = _MemoryUserDataRepository();
    final container = ProviderContainer(overrides: [
      userDataRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(userDataProvider.notifier);
    await notifier.load('alice');
    await expectLater(
      notifier.persist('bob', UserData.empty()),
      throwsA(isA<StateError>()),
    );
  });

  test('a failed persistence attempt is surfaced to the caller', () async {
    final repository = _MemoryUserDataRepository()..failNextSave = true;
    final container = ProviderContainer(overrides: [
      userDataRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(userDataProvider.notifier);
    await notifier.load('alice');
    await expectLater(
      notifier.persist('alice', UserData.empty()),
      throwsA(isA<StateError>()),
    );
  });
}
