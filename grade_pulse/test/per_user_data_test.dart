import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/services/auth_service.dart';
import 'package:grade_pulse/services/data_codec.dart';
import 'package:grade_pulse/services/data_transfer.dart';
import 'package:grade_pulse/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('importing into one account never touches another account', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final storage = StorageService(prefs);

    final alice = await auth.signUp(
      name: 'Alice Cruz', email: 'alice@example.com', password: 'alice-secret-1',
    );
    final bob = await auth.signUp(
      name: 'Bob Reyes', email: 'bob@example.com', password: 'bob-secret-22',
    );

    final bobData = sampleData()
      ..terms.first.name = 'Bob only term'
      ..reminders.first.id = 'bob-r';
    await storage.save(bob.id, bobData);
    final bobBefore = prefs.getString('gp_data_v1_${bob.id}');

    // Alice imports (replace) a file and then merges another one.
    final file = DataTransfer.buildExport(sampleData());
    final parsed = UserDataCodec.parse(utf8.decode(file.bytes));
    final aliceStart = await storage.load(alice.id);
    expect(aliceStart.terms, isEmpty);
    final replaced = DataTransfer.apply(ImportMode.replace, aliceStart, parsed.data);
    await storage.save(alice.id, replaced.data);
    final merged = DataTransfer.apply(ImportMode.merge, replaced.data, parsed.data);
    await storage.save(alice.id, merged.data);
    await storage.flush();

    expect(canon(await storage.load(alice.id)), canon(sampleData()));
    expect(prefs.getString('gp_data_v1_${bob.id}'), bobBefore,
        reason: "Bob's stored record must be byte-for-byte unchanged");
    expect(canon(await storage.load(bob.id)), canon(bobData));
  });

  test('a new account starts empty even after another account imported data', () async {
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.save('user-a', sampleData());
    final fresh = await storage.load('user-b');
    expect(DataCounts.of(fresh).isEmpty, isTrue);
  });

  test('exports never contain credentials, hashes, tokens or the email', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final storage = StorageService(prefs);
    final user = await auth.signUp(
      name: 'Alice Cruz', email: 'alice@example.com', password: 'alice-secret-1',
    );
    await storage.save(user.id, sampleData());
    await storage.flush();

    final users = jsonDecode(prefs.getString('gp_users_v1')!) as Map<String, dynamic>;
    final record = users['alice@example.com'] as Map<String, dynamic>;

    final saved = await storage.load(user.id);
    final text = utf8.decode(DataTransfer.buildExport(saved).bytes);

    expect(text, isNot(contains('alice-secret-1')));
    expect(text, isNot(contains(record['hash'] as String)));
    expect(text, isNot(contains(record['salt'] as String)));
    expect(text, isNot(contains('alice@example.com')));
    expect(text, isNot(contains('Alice Cruz')));
    expect(text, isNot(contains(user.id)));
    expect(text.toLowerCase(), isNot(contains('password')));
    expect(text.toLowerCase(), isNot(contains('token')));

    final keys = (jsonDecode(text) as Map<String, dynamic>).keys.toSet();
    expect(keys, {'version', 'meta', 'terms', 'reminders', 'groups', 'settings'});
  });

  group('loading saved records', () {
    test('a version 1 record with missing optional fields loads', () async {
      SharedPreferences.setMockInitialValues({
        'gp_data_v1_u1': '{"version":1,"terms":[{"name":"T","courses":[{"code":"C"}]}]}',
      });
      final storage = StorageService(await SharedPreferences.getInstance());
      final data = await storage.load('u1');
      expect(data.terms.single.courses.single.units, 3);
      expect(data.settings.themeMode, ThemeMode.system);
    });

    test('a corrupted record throws and is left untouched', () async {
      SharedPreferences.setMockInitialValues({'gp_data_v1_u1': '{"version":1,"terms":[{'});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await expectLater(storage.load('u1'), throwsA(isA<StorageException>()));
      expect(prefs.getString('gp_data_v1_u1'), '{"version":1,"terms":[{');
    });

    test('a record from a newer schema is refused, not overwritten', () async {
      const newer = '{"version":99,"terms":[]}';
      SharedPreferences.setMockInitialValues({'gp_data_v1_u1': newer});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      await expectLater(storage.load('u1'), throwsA(isA<StorageException>()));
      expect(prefs.getString('gp_data_v1_u1'), newer);
    });
  });
}
