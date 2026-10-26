import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/services/data_codec.dart';
import 'package:grade_pulse/services/data_transfer.dart';

import 'test_support.dart';

void main() {
  test('current schema is version 4', () {
    expect(UserDataCodec.currentVersion, 4);
    expect(UserData.schemaVersion, 4);
    expect(UserDataCodec.migrations.containsKey(1), isTrue);
    expect(UserDataCodec.migrations.containsKey(2), isTrue);
    expect(UserDataCodec.migrations.containsKey(3), isTrue);
  });

  group('migration from version 1', () {
    const v1 = '''
    {"version":1,
     "terms":[{"name":"T","courses":[{"code":"C","title":"Course","units":3,"assessments":[
       {"title":"Hardware Diagnostics Quiz","scoreAchieved":95,"maxScore":100},
       {"title":"Assembly Midterm Lab","scoreAchieved":92,"maxScore":100},
       {"title":"Midterm Exam","scoreAchieved":80,"maxScore":100},
       {"title":"Final Project","scoreAchieved":90,"maxScore":100},
       {"title":"Research Essay","scoreAchieved":88,"maxScore":100},
       {"title":"Participation","scoreAchieved":10,"maxScore":10}]}]}],
     "settings":{"themeMode":"dark","gpaScale":"Percentage %",
                 "calcCurrent":"90","calcWeight":"60","calcTarget":"92"}}''';

    test('adds a category to every assessment, guessed from its title', () {
      final parsed = UserDataCodec.parse(v1);
      expect(parsed.sourceVersion, 1);
      expect(parsed.wasMigrated, isTrue);
      final cats = parsed.data.terms.single.courses.single.assessments.map((a) => a.category).toList();
      expect(cats, ['Quiz', 'Laboratory', 'Exam', 'Project', 'Assignment', 'Other']);
    });

    test('keeps every existing value and the existing settings keys', () {
      final parsed = UserDataCodec.parse(v1);
      final s = parsed.data.settings;
      expect(s.themeMode, ThemeMode.dark);
      expect(s.gpaScale, 'Percentage %');
      expect(s.calcCurrent, '90');
      expect(s.calcWeight, '60');
      expect(s.calcTarget, '92');
      // new settings take safe defaults
      expect(s.calcRemaining, '');
      expect(s.targetPercent, isNull);
      expect(s.gradeBands, isEmpty);
      final first = parsed.data.terms.single.courses.single.assessments.first;
      expect([first.title, first.scoreAchieved, first.maxScore], ['Hardware Diagnostics Quiz', 95.0, 100.0]);
      expect(parsed.warnings, isEmpty);
    });

    test('an existing category in a v1 file is kept', () {
      final parsed = UserDataCodec.parse(
        '{"version":1,"terms":[{"name":"T","courses":[{"code":"C","assessments":['
        '{"title":"Quiz","category":"Project","scoreAchieved":1,"maxScore":2}]}]}]}',
      );
      expect(parsed.data.terms.single.courses.single.assessments.single.category, 'Project');
    });

    test('malformed v1 content still reports validation errors', () {
      final e = errorOf('{"version":1,"terms":[{"name":"T","courses":[{"code":"C","assessments":[5]}]}]}');
      expect(e.problems.join(), contains('assessments[0]'));
    });

    test('the title guesser', () {
      expect(UserDataCodec.inferCategory('Quiz #3'), 'Quiz');
      expect(UserDataCodec.inferCategory('Chem Lab Report'), 'Laboratory');
      expect(UserDataCodec.inferCategory('Capstone Defense'), 'Project');
      expect(UserDataCodec.inferCategory('Periodical Examination'), 'Exam');
      expect(UserDataCodec.inferCategory('Homework 2'), 'Assignment');
      expect(UserDataCodec.inferCategory('Syllabus review'), 'Other');
      expect(UserDataCodec.inferCategory(''), 'Other');
    });
  });

  group('new fields round trip', () {
    test('categories, calculator inputs, target and grade tables survive', () {
      final original = sampleData();
      final back = UserDataCodec.parse(UserDataCodec.encode(original)).data;
      expect(canon(back), canon(original));
      expect(back.terms.first.courses.first.assessments.map((a) => a.category), ['Quiz', 'Exam']);
      expect(back.settings.calcRemaining, '40');
      expect(back.settings.targetPercent, 90);
      final tup = back.settings.gradeBands['TUP / PLM (1.0 - 5.0)']!;
      expect(tup.map((b) => [b.minPercent, b.grade]), [[95.0, 1.0], [85.0, 2.0], [75.0, 3.0], [0.0, 5.0]]);
    });

    test('defaults are not written when unused', () {
      final json = AppSettings().toJson();
      expect(json.containsKey('targetPercent'), isFalse);
      expect(json.containsKey('gradeBands'), isFalse);
      expect(json['calcRemaining'], '');
      for (final key in ['gpaScale', 'calcCurrent', 'calcWeight', 'calcTarget', 'themeMode']) {
        expect(json.containsKey(key), isTrue, reason: key);
      }
    });

    test('merge keeps the existing target and tables', () {
      final existing = sampleData();
      final incoming = UserData.empty()..settings.targetPercent = 70;
      final o = DataTransfer.apply(ImportMode.merge, existing, incoming);
      expect(o.data.settings.targetPercent, 90);
      expect(o.data.settings.gradeBands, isNotEmpty);
    });

    test('replace brings the imported settings', () {
      final incoming = UserData.empty()..settings.targetPercent = 70;
      final o = DataTransfer.apply(ImportMode.replace, sampleData(), incoming);
      expect(o.data.settings.targetPercent, 70);
      expect(o.data.settings.gradeBands, isEmpty);
    });
  });

  group('validation of the new fields', () {
    String withSettings(String settings) => '{"version":2,"settings":$settings}';

    test('targetPercent must be a number from 1 to 100', () {
      for (final bad in ['0', '101', '-5', '"90"', 'true']) {
        expect(errorOf(withSettings('{"targetPercent":$bad}')).problems.join(), contains('targetPercent'), reason: bad);
      }
      expect(UserDataCodec.parse(withSettings('{"targetPercent":87.5}')).data.settings.targetPercent, 87.5);
      expect(UserDataCodec.parse(withSettings('{"targetPercent":null}')).data.settings.targetPercent, isNull);
    });

    test('calcRemaining must be text', () {
      expect(errorOf(withSettings('{"calcRemaining":40}')).problems.join(), contains('calcRemaining'));
    });

    test('gradeBands are checked', () {
      const scale = 'TUP / PLM (1.0 - 5.0)';
      expect(errorOf(withSettings('{"gradeBands":[]}')).problems.join(), contains('gradeBands'));
      expect(errorOf(withSettings('{"gradeBands":{"$scale":"x"}}')).problems.join(), contains('list of rows'));
      expect(errorOf(withSettings('{"gradeBands":{"$scale":[{"min":"a","grade":1}]}}')).problems.join(), contains('numeric'));
      expect(errorOf(withSettings('{"gradeBands":{"$scale":[{"min":50,"grade":1}]}}')).problems.join(), contains('0%'));
      expect(errorOf(withSettings('{"gradeBands":{"$scale":[{"min":0,"grade":1},{"min":0,"grade":2}]}}')).problems.join(), contains('same'));
      final ok = UserDataCodec.parse(withSettings('{"gradeBands":{"$scale":[{"min":60,"grade":3},{"min":0,"grade":5}]}}'));
      expect(ok.data.settings.gradeBands[scale], hasLength(2));
      expect(ok.warnings, isEmpty);
    });

    test('tables for scales without one are reported, not dropped silently', () {
      final parsed = UserDataCodec.parse(
        withSettings('{"gradeBands":{"Percentage %":[{"min":0,"grade":0}],"Mystery":[]}}'),
      );
      expect(parsed.warnings, hasLength(2));
      expect(parsed.data.settings.gradeBands, isEmpty);
    });

    test('assessment category and score warnings', () {
      final parsed = UserDataCodec.parse('''
      {"version":2,"terms":[{"name":"T","courses":[{"code":"C","assessments":[
        {"title":"A","category":"Pop quiz","scoreAchieved":12,"maxScore":10}]}]}]}''');
      final a = parsed.data.terms.single.courses.single.assessments.single;
      expect(a.category, 'Other');
      expect(a.scoreAchieved, 12, reason: 'the score itself is never altered on import');
      expect(parsed.warnings.join(), contains('Pop quiz'));
      expect(parsed.warnings.join(), contains('above the maximum'));
    });

    test('non-text category is an error', () {
      final e = errorOf('{"version":2,"terms":[{"name":"T","courses":[{"code":"C","assessments":['
          '{"title":"A","category":5,"scoreAchieved":1,"maxScore":2}]}]}]}');
      expect(e.problems.join(), contains('category'));
    });
  });

  group('schema v4 profile metadata', () {
    test('v3 files migrate with an empty profile', () {
      final parsed = UserDataCodec.parse(
        '{"version":3,"terms":[],"reminders":[],"groups":[],"settings":{"themeMode":"dark"}}',
      );
      expect(parsed.sourceVersion, 3);
      expect(parsed.wasMigrated, isTrue);
      expect(parsed.data.profile.hasContent, isFalse);
      expect(parsed.data.settings.themeMode, ThemeMode.dark);
    });

    test('profile metadata survives export/import without authentication identity', () {
      final data = sampleData();
      data.profile = StudentProfile(
        school: 'Technological University of the Philippines - Taguig',
        program: 'BTVTED - Computer Hardware Servicing',
        yearLevel: '2nd Year',
        studentInfo: 'Section CHS-2A',
      );
      final text = UserDataCodec.encode(data);
      expect(text, isNot(contains('password')));
      expect(text, isNot(contains('email')));
      final back = UserDataCodec.parse(text).data;
      expect(back.profile.school, data.profile.school);
      expect(back.profile.program, data.profile.program);
      expect(back.profile.yearLevel, data.profile.yearLevel);
      expect(back.profile.studentInfo, data.profile.studentInfo);
    });

    test('profile must be an object containing text values', () {
      expect(errorOf('{"version":4,"profile":[]}').problems.join(), contains('profile'));
      expect(errorOf('{"version":4,"profile":{"school":5}}').problems.join(), contains('profile.school'));
    });

    test('merge keeps current profile; replace imports profile metadata', () {
      final existing = sampleData()..profile.school = 'Existing School';
      final incoming = UserData.empty()..profile.school = 'Backup School';
      expect(DataTransfer.apply(ImportMode.merge, existing, incoming).data.profile.school, 'Existing School');
      expect(DataTransfer.apply(ImportMode.replace, existing, incoming).data.profile.school, 'Backup School');
    });
  });

  test('JSON written by the app stays valid JSON with the expected top-level keys', () {
    final map = jsonDecode(UserDataCodec.encode(sampleData())) as Map<String, dynamic>;
    expect(map.keys.toSet(), {'version', 'meta', 'terms', 'reminders', 'groups', 'settings', 'profile'});
    expect(map['version'], 4);
  });
}
