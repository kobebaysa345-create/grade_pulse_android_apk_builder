import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/services/analytics.dart';
import 'package:grade_pulse/services/data_codec.dart';
import 'package:grade_pulse/services/data_transfer.dart';


Assessment a(String title, double score, [double max = 100, String cat = 'Quiz']) =>
    Assessment(title: title, category: cat, scoreAchieved: score, maxScore: max);

Course c(String code, int units, List<Assessment> list) =>
    Course(code: code, title: 'Title $code', units: units, assessments: list);

List<AcademicTerm> realTerms() => [
  AcademicTerm(name: 'Y1 T1', courses: [
    c('IT 101', 3, [a('Quiz 1', 95), a('Exam', 85, 100, 'Exam')]), // 90
    c('MATH 101', 3, [a('Quiz 1', 60)]), // 60 -> low score
    c('NSTP', 3, []), // no assessments
  ]),
  AcademicTerm(name: 'Y1 T2', courses: [
    c('IT 102', 3, [a('Lab 1', 96, 100, 'Laboratory')]), // 96
    c('HIST 101', 1, [a('Essay', 80)]), // 80
  ]),
];

void main() {
  test('no data gives empty analytics, never invented numbers', () {
    final stats = AcademicAnalytics.compute([], AppSettings());
    expect(stats.hasData, isFalse);
    expect(stats.cumulativePercent, isNull);
    expect(stats.cumulativeGrade, isNull);
    expect(stats.terms, isEmpty);
    expect(stats.subjects, isEmpty);
    expect(stats.strongest, isNull);
    expect(stats.lowest, isNull);
    expect(stats.hasTrend, isFalse);
    expect(stats.target, isNull);
    expect(stats.attention, isEmpty);
  });

  test('subjects with no assessments produce no averages', () {
    final stats = AcademicAnalytics.compute(
      [AcademicTerm(name: 'T', courses: [c('X', 3, [])])],
      AppSettings(),
    );
    expect(stats.hasData, isFalse);
    expect(stats.subjectCount, 1);
    expect(stats.totalUnits, 3);
    expect(stats.gradedUnits, 0);
    expect(stats.attention.single.kind, AttentionKind.noGrades);
  });

  test('cumulative and term results are unit-weighted', () {
    final stats = AcademicAnalytics.compute(realTerms(), AppSettings());
    // Term 1 graded: IT 101 (3u, 90) + MATH 101 (3u, 60)  => 75
    expect(stats.terms[0].percent, closeTo(75.0, 1e-9));
    // Term 2: (3 x 96 + 1 x 80) / 4 = 92
    expect(stats.terms[1].percent, closeTo(92.0, 1e-9));
    // Cumulative: (3x90 + 3x60 + 3x96 + 1x80) / 10 = 81.8
    expect(stats.cumulativePercent, closeTo(81.8, 1e-9));
    expect(stats.totalUnits, 13); // includes the ungraded 3-unit subject
    expect(stats.gradedUnits, 10);
    expect(stats.subjectCount, 5);
    expect(stats.gradedSubjectCount, 4);
    expect(stats.assessmentCount, 5);
    expect(stats.currentTerm!.name, 'Y1 T2');
  });

  test('grades follow the active scale', () {
    final s = AppSettings(gpaScale: 'TUP / PLM (1.0 - 5.0)');
    final stats = AcademicAnalytics.compute(realTerms(), s);
    // IT 101 90 -> 1.75, MATH 60 -> 5.0, IT 102 96 -> 1.25, HIST 80 -> 2.5
    // (3x1.75 + 3x5 + 3x1.25 + 1x2.5) / 10 = 2.65
    expect(stats.cumulativeGrade, closeTo(2.65, 1e-9));
  });

  test('strongest and lowest subjects come from recorded results', () {
    final stats = AcademicAnalytics.compute(realTerms(), AppSettings());
    expect(stats.strongest!.code, 'IT 102');
    expect(stats.lowest!.code, 'MATH 101');
    expect(stats.subjects.map((s) => s.code), ['IT 102', 'IT 101', 'HIST 101', 'MATH 101']);

    final one = AcademicAnalytics.compute(
      [AcademicTerm(name: 'T', courses: [c('ONLY', 3, [a('q', 80)])])],
      AppSettings(),
    );
    expect(one.strongest!.code, 'ONLY');
    expect(one.lowest, isNull, reason: 'needs two subjects to compare');
  });

  test('trend needs two graded terms', () {
    final stats = AcademicAnalytics.compute(realTerms(), AppSettings());
    expect(stats.hasTrend, isTrue);
    expect(stats.trend.map((t) => t.name), ['Y1 T1', 'Y1 T2']);
    expect(stats.trendDelta, closeTo(17.0, 1e-9));

    final single = AcademicAnalytics.compute([realTerms().first], AppSettings());
    expect(single.hasTrend, isFalse);
    expect(single.trendDelta, isNull);

    // a second term with no grades does not create a trend point
    final withEmpty = AcademicAnalytics.compute(
      [realTerms().first, AcademicTerm(name: 'Empty', courses: [c('Z', 3, [])])],
      AppSettings(),
    );
    expect(withEmpty.hasTrend, isFalse);
  });

  test('target progress', () {
    final s = AppSettings(targetPercent: 90);
    final stats = AcademicAnalytics.compute(realTerms(), s);
    expect(stats.target!.targetPercent, 90);
    expect(stats.target!.gap, closeTo(8.2, 1e-9));
    expect(stats.target!.reached, isFalse);
    expect(stats.target!.fraction, closeTo(81.8 / 90, 1e-9));

    final reached = AcademicAnalytics.compute(realTerms(), AppSettings(targetPercent: 80));
    expect(reached.target!.reached, isTrue);
    expect(reached.target!.fraction, 1.0);

    expect(AcademicAnalytics.compute(realTerms(), AppSettings()).target, isNull);
    final noGrades = AcademicAnalytics.compute([], AppSettings(targetPercent: 90));
    expect(noGrades.target!.currentPercent, isNull);
    expect(noGrades.target!.gap, isNull);
    expect(noGrades.target!.fraction, 0);
  });

  test('assessments that need attention', () {
    final stats = AcademicAnalytics.compute(realTerms(), AppSettings(targetPercent: 85));
    final titles = stats.attention.map((i) => i.title).toList();
    expect(titles.any((t) => t.contains('Quiz 1 (MATH 101): 60.0%')), isTrue);
    expect(titles.any((t) => t.contains('NSTP has no assessments')), isTrue);
    expect(titles.any((t) => t.contains('MATH 101 is below your target')), isTrue);
    // 95% and 85% scores are fine
    expect(titles.any((t) => t.contains('IT 101)')), isFalse);
    expect(stats.attentionTotal, stats.attention.length);

    final over = AcademicAnalytics.compute(
      [AcademicTerm(name: 'T', courses: [c('X', 3, [a('Bonus', 12, 10)])])],
      AppSettings(),
    );
    expect(over.attention.single.kind, AttentionKind.overMax);
  });

  test('sample (demo) terms never count as real results', () {
    final terms = [
      ...realTerms(),
      AcademicTerm(name: 'Sample', isDemo: true, courses: [c('DEMO', 3, [a('x', 100)])]),
    ];
    final withSample = AcademicAnalytics.compute(terms, AppSettings());
    final without = AcademicAnalytics.compute(realTerms(), AppSettings());
    expect(withSample.excludedSampleTerms, 1);
    expect(withSample.cumulativePercent, without.cumulativePercent);
    expect(withSample.subjects.any((s) => s.code == 'DEMO'), isFalse);

    final onlySample = AcademicAnalytics.compute(
      [AcademicTerm(name: 'Sample', isDemo: true, courses: [c('DEMO', 3, [a('x', 100)])])],
      AppSettings(),
    );
    expect(onlySample.hasData, isFalse);
  });

  test('results update immediately when an assessment changes', () {
    final terms = realTerms();
    final before = AcademicAnalytics.compute(terms, AppSettings()).cumulativePercent!;
    terms[0].courses[1].assessments.first.scoreAchieved = 100; // MATH 60 -> 100
    final after = AcademicAnalytics.compute(terms, AppSettings()).cumulativePercent!;
    expect(after, greaterThan(before));
    expect(after, closeTo((3 * 90 + 3 * 100 + 3 * 96 + 80) / 10, 1e-9));
    terms[0].courses[1].assessments.clear();
    expect(
      AcademicAnalytics.compute(terms, AppSettings()).cumulativePercent,
      closeTo((3 * 90 + 3 * 96 + 80) / 7, 1e-9),
    );
  });

  test('export then import gives identical analytics', () {
    final data = UserData(
      terms: realTerms(),
      reminders: [],
      groups: [],
      settings: AppSettings(gpaScale: 'TUP / PLM (1.0 - 5.0)', targetPercent: 85),
    );
    final file = DataTransfer.buildExport(data);
    final back = UserDataCodec.parse(utf8.decode(file.bytes)).data;

    final x = AcademicAnalytics.compute(data.terms, data.settings);
    final y = AcademicAnalytics.compute(back.terms, back.settings);
    expect(y.cumulativePercent, x.cumulativePercent);
    expect(y.cumulativeGrade, x.cumulativeGrade);
    expect(y.totalUnits, x.totalUnits);
    expect(y.subjects.map((s) => '${s.code}:${s.percent}'), x.subjects.map((s) => '${s.code}:${s.percent}'));
    expect(y.terms.map((t) => t.percent), x.terms.map((t) => t.percent));
    expect(y.trendDelta, x.trendDelta);
    expect(y.attention.map((i) => i.title), x.attention.map((i) => i.title));
    expect(y.target!.gap, x.target!.gap);
  });

  test('analytics are never part of the exported JSON', () {
    final data = UserData(terms: realTerms(), reminders: [], groups: [], settings: AppSettings());
    final text = utf8.decode(DataTransfer.buildExport(data).bytes);
    for (final word in ['cumulative', 'average', 'trend', 'strongest', 'lowest', 'attention']) {
      expect(text.toLowerCase(), isNot(contains('"$word')), reason: word);
    }
    final settings = (jsonDecode(text) as Map)['settings'] as Map;
    expect(settings.keys.toSet(), {
      'themeMode', 'gpaScale', 'calcCurrent', 'calcWeight', 'calcRemaining', 'calcTarget',
      'calcQuiz', 'calcRecitation', 'calcGroupActivities', 'calcSelfCheck',
      'calcUnitTest1', 'calcUnitTest2', 'calcTermTest',
    });
  });
}
