import 'package:flutter_test/flutter_test.dart';
import 'package:grade_pulse/models/models.dart';
import 'package:grade_pulse/services/grade_math.dart';

Course course(String code, int units, List<double> scores) => Course(
  code: code,
  title: code,
  units: units,
  assessments: [
    for (var i = 0; i < scores.length; i++)
      Assessment(title: 'A$i', scoreAchieved: scores[i], maxScore: 100),
  ],
);

CalcResult solve(String cur, String done, String target, {String rem = ''}) =>
    GradeCalculator.solve(current: cur, completed: done, remaining: rem, target: target);

void main() {
  group('required remaining score formula', () {
    test('(target - current x completed) / remaining, weights as fractions', () {
      // (92 - 90 x 0.6) / 0.4 = 95
      final r = solve('90', '60', '92');
      expect(r.status, CalcStatus.achievable);
      expect(r.requiredScore, closeTo(95.0, 1e-9));
      expect(r.remainingWeight, 40);
    });

    test('results change with the inputs (nothing is hardcoded)', () {
      expect(solve('80', '50', '90').requiredScore, closeTo(100.0, 1e-9));
      expect(solve('85', '70', '88').requiredScore, closeTo(95.0, 1e-9));
      expect(solve('70', '25', '75').requiredScore, closeTo((75 - 70 * 0.25) / 0.75, 1e-9));
    });

    test('an explicit, consistent remaining weight gives the same answer', () {
      expect(solve('90', '60', '92', rem: '40').requiredScore, closeTo(95.0, 1e-9));
    });

    test('nothing completed: the required score equals the target', () {
      final r = solve('0', '0', '88');
      expect(r.status, CalcStatus.achievable);
      expect(r.requiredScore, closeTo(88.0, 1e-9));
    });

    test('projected final grade for a given remaining score', () {
      final r = solve('90', '60', '92');
      expect(r.projectedFinal(95), closeTo(92.0, 1e-9));
      expect(r.projectedFinal(100), closeTo(94.0, 1e-9));
      expect(r.projectedFinal(0), closeTo(54.0, 1e-9));
      expect(r.maxPossible, closeTo(94.0, 1e-9));
      expect(r.lowestPossible, closeTo(54.0, 1e-9));
    });
  });

  group('goal status', () {
    test('impossible target reports the real figure, not a clamped one', () {
      final r = solve('60', '80', '95'); // (95 - 48) / 0.2 = 235
      expect(r.status, CalcStatus.impossible);
      expect(r.requiredScore, closeTo(235.0, 1e-9));
      expect(r.message, contains('Not achievable'));
      expect(r.maxPossible, closeTo(68.0, 1e-9));
    });

    test('exactly 100% needed is still achievable', () {
      expect(solve('80', '50', '90').status, CalcStatus.achievable);
    });

    test('already secured target', () {
      final r = solve('100', '90', '80'); // (80 - 90) / 0.1 < 0
      expect(r.status, CalcStatus.secured);
      expect(r.requiredScore, 0);
    });

    test('completed weight of 100% does not divide by zero', () {
      final met = solve('85', '100', '80');
      expect(met.status, CalcStatus.secured);
      expect(met.requiredScore, isNull);
      final missed = solve('85', '100', '90');
      expect(missed.status, CalcStatus.impossible);
      expect(missed.requiredScore, isNull);
      expect(missed.message, contains('All the weight is completed'));
      // completed 100 with remaining 0 given explicitly
      expect(solve('85', '100', '90', rem: '0').status, CalcStatus.impossible);
    });
  });

  group('input validation', () {
    test('missing values are reported as incomplete', () {
      final r = solve('', '60', '');
      expect(r.status, CalcStatus.incomplete);
      expect(r.message, contains('current average'));
      expect(r.message, contains('target'));
      expect(r.isValid, isFalse);
    });

    test('non-numbers, NaN and infinity are invalid', () {
      for (final bad in ['abc', 'NaN', 'Infinity', '1e999', '--5']) {
        expect(solve(bad, '60', '90').status, CalcStatus.invalid, reason: bad);
        expect(solve('90', bad, '90').status, CalcStatus.invalid, reason: bad);
        expect(solve('90', '60', bad).status, CalcStatus.invalid, reason: bad);
      }
    });

    test('negative values and values above 100 are rejected', () {
      expect(solve('-1', '60', '90').status, CalcStatus.invalid);
      expect(solve('101', '60', '90').status, CalcStatus.invalid);
      expect(solve('90', '-5', '90').status, CalcStatus.invalid);
      expect(solve('90', '120', '90').status, CalcStatus.invalid);
      expect(solve('90', '60', '101').status, CalcStatus.invalid);
      expect(solve('90', '60', '-3').status, CalcStatus.invalid);
      expect(solve('90', '60', '90', rem: '-1').status, CalcStatus.invalid);
      expect(solve('90', '60', '90', rem: '150').status, CalcStatus.invalid);
    });

    test('completed and remaining weight must add up to 100', () {
      final r = solve('90', '60', '92', rem: '30');
      expect(r.status, CalcStatus.invalid);
      expect(r.message, contains('add up to 100%'));
      expect(r.requiredScore, isNull);
    });

    test('a % sign, spaces and a decimal comma are accepted', () {
      expect(GradeCalculator.parse(' 90% '), 90);
      expect(GradeCalculator.parse('90,5'), 90.5);
      expect(GradeCalculator.parse(''), isNull);
      expect(GradeCalculator.parse('  '), isNull);
    });
  });

  group('unit-weighted results', () {
    test('weighted by units, not a plain mean of subjects', () {
      final courses = [course('A', 3, [90]), course('B', 1, [70])];
      expect(GradeMath.weightedPercent(courses), closeTo(85.0, 1e-9)); // not 80
    });

    test('subjects without assessments are left out, not counted as 0%', () {
      final courses = [course('A', 3, [90]), Course(code: 'B', title: 'B', units: 5, assessments: [])];
      expect(GradeMath.weightedPercent(courses), closeTo(90.0, 1e-9));
      expect(GradeMath.gradedUnits(courses), 3);
      expect(GradeMath.totalUnits(courses), 8);
      expect(GradeMath.weightedPercent([courses[1]]), isNull);
      expect(GradeMath.weightedPercent(const <Course>[]), isNull);
    });

    test('a subject average is points earned over points possible', () {
      final c = Course(code: 'X', title: 'X', units: 3, assessments: [
        Assessment(title: 'a', scoreAchieved: 10, maxScore: 10),
        Assessment(title: 'b', scoreAchieved: 0, maxScore: 90),
      ]);
      expect(c.percent, closeTo(10.0, 1e-9));
    });

    test('each subject is converted to a grade, then averaged by units', () {
      final courses = [course('A', 3, [90]), course('B', 1, [70])];
      final s = AppSettings();
      // 4.0 table: 90 -> 3.7, 70 -> 1.7  =>  (3.7 x 3 + 1.7) / 4
      expect(GradeMath.weightedGrade(courses, GradeScales.gpa, s), closeTo(3.2, 1e-9));
      // TUP table: 90 -> 1.75, 70 -> 5.0  =>  (1.75 x 3 + 5.0) / 4
      expect(GradeMath.weightedGrade(courses, GradeScales.tup, s), closeTo(2.5625, 1e-9));
      expect(GradeMath.weightedGrade(courses, GradeScales.percentage, s), closeTo(85.0, 1e-9));
    });
  });

  group('grade conversion tables', () {
    test('the 4.0 GPA is not a straight line from the percentage', () {
      final s = AppSettings();
      // linear would give 3.6 for 90% and 3.72 for 93%
      expect(GradeScales.convert(90, GradeScales.gpa, s), 3.7);
      expect(GradeScales.convert(93, GradeScales.gpa, s), 4.0);
      expect(GradeScales.convert(92.99, GradeScales.gpa, s), 3.7);
      expect(GradeScales.convert(0, GradeScales.gpa, s), 0.0);
      expect(GradeScales.convert(100, GradeScales.gpa, s), 4.0);
    });

    test('TUP / PLM table and boundaries (lower is better)', () {
      final s = AppSettings();
      expect(GradeScales.convert(98, GradeScales.tup, s), 1.0);
      expect(GradeScales.convert(75, GradeScales.tup, s), 3.0);
      expect(GradeScales.convert(74.99, GradeScales.tup, s), 5.0);
      expect(GradeScales.higherIsBetter(GradeScales.tup), isFalse);
      expect(GradeScales.higherIsBetter(GradeScales.gpa), isTrue);
    });

    test('percentage scale returns the percentage itself', () {
      expect(GradeScales.convert(87.26, GradeScales.percentage, AppSettings()), 87.26);
      expect(GradeScales.formatGrade(87.26, GradeScales.percentage), '87.3%');
    });

    test('a user-edited table is used and identified', () {
      final s = AppSettings(gradeBands: {
        GradeScales.tup: const [GradeBand(90, 1.0), GradeBand(0, 5.0)],
      });
      expect(GradeScales.convert(91, GradeScales.tup, s), 1.0);
      expect(GradeScales.convert(89, GradeScales.tup, s), 5.0);
      expect(GradeScales.isCustomised(s, GradeScales.tup), isTrue);
      expect(GradeScales.isCustomised(s, GradeScales.gpa), isFalse);
      s.gpaScale = GradeScales.tup;
      expect(GradeScales.describeActive(s), contains('your edited table'));
      s.gpaScale = GradeScales.gpa;
      expect(GradeScales.describeActive(s), contains('not an official'));
      s.gpaScale = GradeScales.percentage;
      expect(GradeScales.describeActive(s), contains('Percentage'));
    });

    test('table validation', () {
      expect(GradeScales.validateBands(const []), isNotNull);
      expect(GradeScales.validateBands(const [GradeBand(50, 1)]), contains('0%'));
      expect(GradeScales.validateBands(const [GradeBand(0, 1), GradeBand(0, 2)]), contains('same'));
      expect(GradeScales.validateBands(const [GradeBand(0, -1)]), isNotNull);
      expect(GradeScales.validateBands(const [GradeBand(101, 1), GradeBand(0, 0)]), isNotNull);
      expect(GradeScales.validateBands(const [GradeBand(60, 1), GradeBand(0, 0)]), isNull);
      expect(GradeScales.validateBands(GradeScales.defaultBands(GradeScales.gpa)), isNull);
      expect(GradeScales.validateBands(GradeScales.defaultBands(GradeScales.tup)), isNull);
    });
  });
}
