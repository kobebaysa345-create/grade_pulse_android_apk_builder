import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/services/data_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fully populated data set that exercises every supported field.
UserData sampleData() => UserData(
  terms: [
    AcademicTerm(
      name: '1st Year - 1st Term',
      isDemo: false,
      courses: [
        Course(
          code: 'IT 101',
          title: 'Intro to Computing',
          units: 3,
          assessments: [
            Assessment(title: 'Quiz 1', category: 'Quiz', scoreAchieved: 17.5, maxScore: 20),
            Assessment(title: 'Midterm', category: 'Exam', scoreAchieved: 88, maxScore: 100),
          ],
        ),
        Course(code: 'HIST 101', title: 'Philippine History', units: 2, assessments: []),
      ],
    ),
  ],
  reminders: [
    Reminder(
      id: 'r1',
      title: 'Midterm Exam',
      courseCode: 'IT 101',
      category: 'Exam',
      dateTime: DateTime(2026, 10, 21, 9, 30),
      isCompleted: true,
    ),
  ],
  groups: [
    StudyGroup(id: 'g1', name: 'Study Team', members: ['Ana', 'You'], notes: 'Meet Friday'),
  ],
  settings: AppSettings(
    themeMode: ThemeMode.dark,
    gpaScale: 'Percentage %',
    calcCurrent: '90',
    calcWeight: '60',
    calcRemaining: '40',
    calcTarget: '92',
    targetPercent: 90,
    gradeBands: {
      'TUP / PLM (1.0 - 5.0)': const [
        GradeBand(95, 1.0),
        GradeBand(85, 2.0),
        GradeBand(75, 3.0),
        GradeBand(0, 5.0),
      ],
    },
  ),
);

/// Canonical text form of data, for equality checks.
String canon(UserData d) => jsonEncode(d.toJson());

/// Parses [raw] and returns the thrown error (fails the test if none).
JsonDataException errorOf(String raw) {
  try {
    UserDataCodec.parse(raw);
  } on JsonDataException catch (e) {
    return e;
  }
  fail('Expected a JsonDataException for: $raw');
}
