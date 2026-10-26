import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/services/data_codec.dart';
import 'package:grade_pulse/services/data_transfer.dart';

import 'test_support.dart';

void main() {
  group('replace', () {
    test('uses the imported data exactly and does not alias it', () {
      final existing = sampleData();
      final incoming = UserData.empty()
        ..terms.add(AcademicTerm(name: 'Other', courses: []));
      final before = canon(incoming);

      final outcome = DataTransfer.apply(ImportMode.replace, existing, incoming);
      expect(canon(outcome.data), before);

      outcome.data.terms.first.name = 'changed';
      expect(canon(incoming), before, reason: 'result must be a copy');
    });

    test('replaces settings too', () {
      final incoming = UserData.empty(themeMode: ThemeMode.light);
      final outcome = DataTransfer.apply(ImportMode.replace, sampleData(), incoming);
      expect(outcome.data.settings.themeMode, ThemeMode.light);
    });
  });

  group('merge', () {
    test('adds only what is missing, keeps settings, never edits inputs', () {
      final existing = sampleData();
      final incoming = sampleData();
      // brand-new records in the incoming data
      incoming.terms.first.courses.first.assessments.add(
        Assessment(title: 'Final', scoreAchieved: 90, maxScore: 100),
      );
      incoming.terms.first.courses.add(
        Course(code: 'MATH 101', title: 'Algebra', units: 3, assessments: [
          Assessment(title: 'Q1', scoreAchieved: 8, maxScore: 10),
        ]),
      );
      incoming.terms.add(AcademicTerm(name: '1st Year - 2nd Term', courses: [
        Course(code: 'PE 101', title: 'PE', units: 2, assessments: []),
      ]));
      incoming.reminders.add(Reminder(
        id: 'r2', title: 'New', courseCode: '', category: 'Personal',
        dateTime: DateTime(2026, 11, 1),
      ));
      incoming.groups.add(StudyGroup(id: 'g2', name: 'Second', members: ['X']));
      incoming.settings.themeMode = ThemeMode.light;

      final existingBefore = canon(existing);
      final incomingBefore = canon(incoming);

      final o = DataTransfer.apply(ImportMode.merge, existing, incoming);

      expect(canon(existing), existingBefore);
      expect(canon(incoming), incomingBefore);

      final d = o.data;
      expect(d.terms.map((t) => t.name), ['1st Year - 1st Term', '1st Year - 2nd Term']);
      expect(d.terms.first.courses.map((c) => c.code), ['IT 101', 'HIST 101', 'MATH 101']);
      expect(d.terms.first.courses.first.assessments.map((a) => a.title), ['Quiz 1', 'Midterm', 'Final']);
      expect(d.reminders.map((r) => r.id), ['r1', 'r2']);
      expect(d.groups.map((g) => g.id), ['g1', 'g2']);
      expect(d.settings.themeMode, ThemeMode.dark, reason: 'merge keeps settings');

      expect(o.added.terms, 1);
      expect(o.added.subjects, 2); // MATH 101 + PE 101
      expect(o.added.assessments, 2); // Final + Q1
      expect(o.added.reminders, 1);
      expect(o.added.groups, 1);
      // 2 identical assessments + 1 identical reminder + 1 identical group
      expect(o.skippedDuplicates, 4);
      expect(o.keptBoth, 0);
    });

    test('merging the same data twice changes nothing', () {
      final o = DataTransfer.apply(ImportMode.merge, sampleData(), sampleData());
      expect(canon(o.data), canon(sampleData()));
      expect(o.added.isEmpty, isTrue);
    });

    test('matching is case- and space-insensitive for names and codes', () {
      final incoming = UserData.empty()
        ..terms.add(AcademicTerm(name: ' 1st year - 1st term ', courses: [
          Course(code: 'it 101', title: 'x', units: 1, assessments: [
            Assessment(title: ' quiz 1', scoreAchieved: 17.5, maxScore: 20),
          ]),
        ]));
      final o = DataTransfer.apply(ImportMode.merge, sampleData(), incoming);
      expect(o.data.terms, hasLength(1));
      expect(o.data.terms.first.courses, hasLength(2));
      expect(o.skippedDuplicates, 1);
    });

    test('same id with different content keeps both, never overwrites', () {
      final existing = sampleData();
      final incoming = UserData.empty()
        ..reminders.add(Reminder(
          id: 'r1', title: 'Different title', courseCode: '', category: 'Exam',
          dateTime: DateTime(2026, 12, 1),
        ))
        ..groups.add(StudyGroup(id: 'g1', name: 'Different group', members: []));

      final o = DataTransfer.apply(ImportMode.merge, existing, incoming);
      expect(o.data.reminders.map((r) => r.title), ['Midterm Exam', 'Different title']);
      expect(o.data.reminders.map((r) => r.id).toSet(), hasLength(2));
      expect(o.data.reminders.last.id, 'r1-imported');
      expect(o.data.groups.map((g) => g.name), ['Study Team', 'Different group']);
      expect(o.data.groups.last.id, 'g1-imported');
      expect(o.keptBoth, 2);
    });

    test('remaps linked reminders when a conflicting group ID is kept as a second group', () {
      final incoming = UserData.empty()
        ..groups.add(StudyGroup(id: 'g1', name: 'A different group', members: ['Kai']))
        ..reminders.add(Reminder(
          id: 'linked-session',
          title: 'Group review',
          courseCode: 'IT 101',
          category: 'Group Study',
          dateTime: DateTime(2026, 11, 4, 15),
          groupId: 'g1',
        ));
      final result = DataTransfer.apply(ImportMode.merge, sampleData(), incoming).data;
      expect(result.groups.last.id, 'g1-imported');
      expect(result.reminders.last.groupId, 'g1-imported');
      expect(UserDataCodec.parse(UserDataCodec.encode(result)).data.reminders.last.groupId, 'g1-imported');
    });

    test('merging into an empty account equals the imported data', () {
      final o = DataTransfer.apply(ImportMode.merge, UserData.empty(), sampleData());
      expect(canon(o.data.copyWithoutSettings()), canon(sampleData().copyWithoutSettings()));
    });
  });

  group('export', () {
    test('builds a verified, re-importable file', () {
      final file = DataTransfer.buildExport(sampleData(), now: DateTime(2026, 10, 18, 21, 5));
      expect(file.fileName, 'grade_pulse_export_20261018_2105.json');
      expect(file.counts.terms, 1);
      expect(file.counts.subjects, 2);
      expect(file.counts.assessments, 2);

      final back = UserDataCodec.parse(utf8.decode(file.bytes));
      expect(canon(back.data), canon(sampleData()));
    });

    test('export then merge-import into the same account adds nothing', () {
      final file = DataTransfer.buildExport(sampleData());
      final back = UserDataCodec.parse(utf8.decode(file.bytes));
      final o = DataTransfer.apply(ImportMode.merge, sampleData(), back.data);
      expect(o.added.isEmpty, isTrue);
    });

    test('counts describe the data', () {
      final c = DataCounts.of(sampleData());
      expect([c.terms, c.subjects, c.assessments, c.reminders, c.groups], [1, 2, 2, 1, 1]);
      expect(DataCounts.of(UserData.empty()).isEmpty, isTrue);
    });
  });
}

extension on UserData {
  /// Same data with default settings, so merge results can be compared
  /// without caring about the (intentionally unchanged) settings.
  UserData copyWithoutSettings() => UserData(
    terms: terms,
    reminders: reminders,
    groups: groups,
    settings: AppSettings(),
  );
}
