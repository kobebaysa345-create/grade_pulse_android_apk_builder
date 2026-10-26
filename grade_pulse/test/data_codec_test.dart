import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/services/data_codec.dart';

import 'test_support.dart';

void main() {
  group('round trip', () {
    test('encode then parse keeps every supported field', () {
      final original = sampleData();
      final text = UserDataCodec.encode(original);
      final parsed = UserDataCodec.parse(text);

      expect(canon(parsed.data), canon(original));
      expect(parsed.warnings, isEmpty);
      expect(parsed.sourceVersion, UserDataCodec.currentVersion);
      expect(parsed.hasSettings, isTrue);
      expect(parsed.data.terms.first.courses.first.assessments.first.scoreAchieved, 17.5);
      expect(parsed.data.terms.first.courses.last.units, 2);
      expect(parsed.data.reminders.first.dateTime, DateTime(2026, 10, 21, 9, 30));
      expect(parsed.data.reminders.first.isCompleted, isTrue);
      expect(parsed.data.settings.themeMode, ThemeMode.dark);
    });

    test('export uses ISO 8601 dates and carries version and meta', () {
      final map = jsonDecode(UserDataCodec.encode(sampleData(),
          exportedAt: DateTime.utc(2026, 10, 18, 13, 5))) as Map<String, dynamic>;
      expect(map['version'], 4);
      expect(map['meta'], {'app': 'grade_pulse', 'exportedAt': '2026-10-18T13:05:00.000Z'});
      final reminder = (map['reminders'] as List).first as Map;
      expect(reminder['dateTime'], '2026-10-21T09:30:00.000');
      expect(DateTime.tryParse(reminder['dateTime'] as String), isNotNull);
    });

    test('empty data round trips', () {
      final text = UserDataCodec.encode(sampleData()..terms.clear());
      expect(UserDataCodec.parse(text).data.terms, isEmpty);
    });
  });

  group('backward compatibility (version 1)', () {
    test('the bundled sample asset parses cleanly', () {
      final raw = File('assets/data/grade_pulse_data.json').readAsStringSync();
      final parsed = UserDataCodec.parse(raw);
      expect(parsed.sourceVersion, 1);
      expect(parsed.wasMigrated, isTrue, reason: 'the asset is a version 1 file');
      expect(parsed.warnings, isEmpty);
      expect(parsed.data.terms, hasLength(1));
      expect(parsed.data.terms.first.courses, hasLength(2));
      expect(
        parsed.data.terms.first.courses.fold<int>(0, (n, c) => n + c.assessments.length),
        3,
      );
      expect(parsed.data.reminders, hasLength(2));
      expect(parsed.data.groups.single.members, ['Devon', 'Maria', 'You']);
      expect(parsed.data.settings.themeMode, ThemeMode.dark);
      expect(parsed.data.settings.calcTarget, '92');
    });

    test('an old file with no version or meta is accepted with a note', () {
      final parsed = UserDataCodec.parse('{"terms": [], "groups": []}');
      expect(parsed.sourceVersion, 1);
      expect(parsed.warnings.single, contains('No "version"'));
    });

    test('a UTF-8 byte-order mark is ignored', () {
      final parsed = UserDataCodec.parse('﻿{"version":1,"terms":[]}');
      expect(parsed.data.terms, isEmpty);
    });

    test('a file saved before the codec existed (plain toJson) still loads', () {
      final legacy = jsonEncode(sampleData().toJson());
      expect(canon(UserDataCodec.parse(legacy).data), canon(sampleData()));
    });
  });

  group('missing optional fields get safe defaults', () {
    test('course without title/units/assessments', () {
      final parsed = UserDataCodec.parse(
        '{"version":1,"terms":[{"name":"T","courses":[{"code":"C1"}]}]}',
      );
      final c = parsed.data.terms.single.courses.single;
      expect(c.title, '');
      expect(c.units, 3);
      expect(c.assessments, isEmpty);
      expect(parsed.data.terms.single.isDemo, isFalse);
      expect(parsed.hasSettings, isFalse);
      expect(parsed.data.settings.themeMode, ThemeMode.system);
      expect(parsed.data.settings.gpaScale, 'Standard 4.0 GPA');
    });

    test('reminder and group without optional fields', () {
      final parsed = UserDataCodec.parse('''
      {"version":1,
       "reminders":[{"id":"a","title":"T","dateTime":"2026-01-02T03:04:05"}],
       "groups":[{"id":"g","name":"G"}]}''');
      final r = parsed.data.reminders.single;
      expect(r.courseCode, '');
      expect(r.category, 'Assignment');
      expect(r.isCompleted, isFalse);
      final g = parsed.data.groups.single;
      expect(g.members, isEmpty);
      expect(g.notes, '');
    });

    test('whole numbers and decimals are both fine for scores', () {
      final parsed = UserDataCodec.parse('''
      {"version":1,"terms":[{"name":"T","courses":[{"code":"C","assessments":[
        {"title":"A","scoreAchieved":9,"maxScore":10.5}]}]}]}''');
      final a = parsed.data.terms.single.courses.single.assessments.single;
      expect(a.scoreAchieved, 9.0);
      expect(a.maxScore, 10.5);
    });
  });

  group('invalid files are rejected with a helpful message', () {
    test('empty file', () => expect(errorOf('   ').message, contains('empty')));

    test('not JSON', () {
      expect(errorOf('{oops').message, contains('not valid JSON'));
      expect(errorOf('hello world').message, contains('not valid JSON'));
    });

    test('truncated / corrupted JSON', () {
      final text = UserDataCodec.encode(sampleData());
      expect(errorOf(text.substring(0, text.length ~/ 2)).message, contains('not valid JSON'));
    });

    test('wrong top-level type', () {
      expect(errorOf('[1,2,3]').message, contains('JSON object'));
    });

    test('incomplete: none of the data sections', () {
      expect(errorOf('{"version":1}').message, contains('incomplete'));
      expect(errorOf('{"name":"something else"}').message, contains('incomplete'));
    });

    test('newer schema version is unsupported', () {
      final e = errorOf('{"version":99,"terms":[]}');
      expect(e.message, contains('version 99'));
      expect(e.message, contains('newer'));
    });

    test('version 0, negative or non-integer is unsupported', () {
      expect(errorOf('{"version":0,"terms":[]}').message, contains('Unsupported'));
      expect(errorOf('{"version":-3,"terms":[]}').message, contains('Unsupported'));
      expect(errorOf('{"version":"1","terms":[]}').message, contains('whole number'));
      expect(errorOf('{"version":1.5,"terms":[]}').message, contains('whole number'));
    });

    test('file from another app', () {
      final e = errorOf('{"version":1,"meta":{"app":"other_app"},"terms":[]}');
      expect(e.message, contains('different app'));
    });

    test('wrong types and bad values are reported with their location', () {
      final e = errorOf('''
      {"version":1,
       "terms":[{"name":"T","courses":[{"code":"C","units":"three","assessments":[
          {"title":"A","scoreAchieved":"ninety","maxScore":0}]}]}],
       "reminders":[{"id":"r","title":"X","dateTime":"not a date"}],
       "groups":[{"id":"g","name":"G","members":[1,2]}],
       "settings":{"calcTarget":92}}''');
      final all = e.problems.join('\n');
      expect(e.message, contains('nothing was imported'));
      expect(all, contains('terms[0].courses[0].units'));
      expect(all, contains('terms[0].courses[0].assessments[0].scoreAchieved'));
      expect(all, contains('terms[0].courses[0].assessments[0].maxScore'));
      expect(all, contains('reminders[0].dateTime'));
      expect(all, contains('groups[0].members'));
      expect(all, contains('settings.calcTarget'));
    });

    test('required fields missing', () {
      final e = errorOf('''
      {"version":1,"terms":[{"courses":[]}],
       "reminders":[{"title":"no id","dateTime":"2026-01-01T00:00:00"}],
       "groups":[{"id":"g"}]}''');
      final all = e.problems.join('\n');
      expect(all, contains('terms[0].name'));
      expect(all, contains('reminders[0].id'));
      expect(all, contains('groups[0].name'));
    });

    test('sections of the wrong type', () {
      final e = errorOf('{"version":1,"terms":{},"reminders":"x","settings":[]}');
      final all = e.problems.join('\n');
      expect(all, contains('terms: must be a list'));
      expect(all, contains('reminders: must be a list'));
      expect(all, contains('settings: must be an object'));
    });

    test('duplicate reminder or group ids are rejected', () {
      final e = errorOf('''
      {"version":1,
       "reminders":[
         {"id":"x","title":"A","dateTime":"2026-01-01T00:00:00"},
         {"id":"x","title":"B","dateTime":"2026-01-02T00:00:00"}],
       "groups":[{"id":"g","name":"A"},{"id":"g","name":"B"}]}''');
      expect(e.problems.where((p) => p.contains('more than once')), hasLength(2));
    });

    test('negative scores and a zero max score are rejected', () {
      final e = errorOf('''
      {"version":1,"terms":[{"name":"T","courses":[{"code":"C","assessments":[
        {"title":"A","scoreAchieved":-1,"maxScore":0}]}]}]}''');
      expect(e.problems, hasLength(2));
    });

    test('many problems are summarised', () {
      final items = List.generate(
        20,
        (i) => '{"id":"r$i","title":"T","dateTime":"bad"}',
      ).join(',');
      final e = errorOf('{"version":1,"reminders":[$items]}');
      expect(e.problems.length, 9); // 8 shown + the "and N more" line
      expect(e.problems.last, contains('12 more'));
    });
  });

  group('nothing is silently dropped', () {
    test('unknown fields are reported as warnings', () {
      final parsed = UserDataCodec.parse('''
      {"version":1,"futureThing":true,
       "terms":[{"name":"T","color":"red","courses":[]}],
       "settings":{"fontSize":12}}''');
      final w = parsed.warnings.join('\n');
      expect(w, contains('futureThing'));
      expect(w, contains('term.color'));
      expect(w, contains('settings.fontSize'));
    });

    test('unknown reminder category is changed visibly', () {
      final parsed = UserDataCodec.parse('''
      {"version":1,"reminders":[
        {"id":"a","title":"T","category":"Lab","dateTime":"2026-01-02T03:04:05"}]}''');
      expect(parsed.data.reminders.single.category, 'Assignment');
      expect(parsed.warnings.single, contains('"Lab"'));
    });

    test('unknown theme or GPA scale falls back with a warning', () {
      final parsed = UserDataCodec.parse(
        '{"version":1,"settings":{"themeMode":"neon","gpaScale":"Weird"}}',
      );
      expect(parsed.data.settings.themeMode, ThemeMode.system);
      expect(parsed.data.settings.gpaScale, 'Standard 4.0 GPA');
      expect(parsed.warnings, hasLength(2));
    });
  });

  group('schema migrations', () {
    // Pretend schema version 2 renamed term "title" to "name".
    final migrations = <int, SchemaMigration>{
      1: (json) {
        final copy = Map<String, dynamic>.from(json);
        copy['terms'] = (json['terms'] as List)
            .map((t) {
              final term = Map<String, dynamic>.from(t as Map);
              term['name'] = term.remove('title');
              return term;
            })
            .toList();
        return copy;
      },
    };

    test('older files are upgraded step by step', () {
      final parsed = UserDataCodec.parse(
        '{"version":1,"terms":[{"title":"Old name","courses":[]}]}',
        migrationsOverride: migrations,
        targetVersion: 2,
      );
      expect(parsed.data.terms.single.name, 'Old name');
      expect(parsed.sourceVersion, 1);
      expect(parsed.wasMigrated, isTrue);
    });

    test('a missing migration step is an error, not a silent load', () {
      try {
        UserDataCodec.parse(
          '{"version":1,"terms":[]}',
          migrationsOverride: const <int, SchemaMigration>{},
          targetVersion: 3,
        );
        fail('should have thrown');
      } on JsonDataException catch (e) {
        expect(e.message, contains('No migration'));
      }
    });

    test('a failing migration is reported', () {
      try {
        UserDataCodec.parse(
          '{"version":1,"terms":[]}',
          migrationsOverride: {1: (_) => throw StateError('boom')},
          targetVersion: 2,
        );
        fail('should have thrown');
      } on JsonDataException catch (e) {
        expect(e.message, contains('failed'));
      }
    });

    test('files newer than the target are refused', () {
      expect(
        () => UserDataCodec.parse('{"version":3,"terms":[]}', targetVersion: 2),
        throwsA(isA<JsonDataException>()),
      );
    });
  });

  group('calendar and study group schema v3', () {
    test('v2 reminder and group records migrate with safe defaults', () {
      const raw = '''{
        "version": 2,
        "reminders": [{"id":"r1","title":"Quiz","courseCode":"IT101","category":"Exam","dateTime":"2026-10-21T09:30:00.000","isCompleted":false}],
        "groups": [{"id":"g1","name":"Team","members":["Ana"],"notes":"Bring notes"}]
      }''';
      final parsed = UserDataCodec.parse(raw);
      expect(parsed.sourceVersion, 2);
      expect(parsed.wasMigrated, isTrue);
      expect(parsed.data.reminders.single.description, '');
      expect(parsed.data.reminders.single.priority, 'Medium');
      expect(parsed.data.reminders.single.groupId, isNull);
      expect(parsed.data.groups.single.courseCode, '');
      expect(parsed.data.groups.single.description, '');
    });

    test('new calendar metadata and group links survive JSON round trip', () {
      final d = sampleData();
      d.reminders.single
        ..description = 'Bring the lab worksheet'
        ..priority = 'High';
      d.groups.single
        ..courseCode = 'IT 101'
        ..description = 'Weekly review team'
        ..createdAt = DateTime(2026, 9, 1);
      d.reminders.single.groupId = d.groups.single.id;
      final returned = UserDataCodec.parse(UserDataCodec.encode(d)).data;
      expect(returned.reminders.single.description, 'Bring the lab worksheet');
      expect(returned.reminders.single.priority, 'High');
      expect(returned.reminders.single.groupId, 'g1');
      expect(returned.groups.single.courseCode, 'IT 101');
      expect(returned.groups.single.description, 'Weekly review team');
      expect(returned.groups.single.createdAt, DateTime(2026, 9, 1));
    });

    test('a reminder cannot reference a missing group', () {
      const raw = '''{
        "version": 3,
        "reminders": [{"id":"r1","title":"Session","dateTime":"2026-10-21T09:30:00.000","groupId":"missing"}],
        "groups": []
      }''';
      expect(() => UserDataCodec.parse(raw), throwsA(isA<JsonDataException>()));
    });
  });

}
