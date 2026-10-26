import '../models/models.dart';
import 'grade_math.dart';

enum AttentionKind { lowScore, overMax, noGrades, belowTarget }

class AttentionItem {
  const AttentionItem(this.kind, this.title, this.detail);
  final AttentionKind kind;
  final String title;
  final String detail;
}

class TermStat {
  const TermStat({
    required this.name,
    required this.subjects,
    required this.gradedSubjects,
    required this.units,
    required this.gradedUnits,
    required this.percent,
    required this.grade,
  });

  final String name;
  final int subjects;
  final int gradedSubjects;
  final int units;
  final int gradedUnits;

  /// Unit-weighted average %, null if no subject in the term has assessments.
  final double? percent;

  /// The same result on the user's active scale.
  final double? grade;
}

class SubjectStat {
  const SubjectStat({
    required this.termName,
    required this.code,
    required this.title,
    required this.units,
    required this.percent,
    required this.assessments,
  });

  final String termName;
  final String code;
  final String title;
  final int units;
  final double percent;
  final int assessments;
}

class TargetProgress {
  const TargetProgress({
    required this.targetPercent,
    required this.currentPercent,
  });

  final double targetPercent;
  final double? currentPercent;

  /// Points still needed (negative = ahead of target). Null without grades.
  double? get gap => currentPercent == null ? null : targetPercent - currentPercent!;

  bool get reached => currentPercent != null && currentPercent! + 1e-9 >= targetPercent;

  /// 0..1 progress bar value.
  double get fraction => currentPercent == null || targetPercent <= 0
      ? 0
      : (currentPercent! / targetPercent).clamp(0.0, 1.0).toDouble();
}

/// Everything on the Insights screen, calculated on demand from the saved
/// terms, subjects and assessments. Nothing here is stored, so it cannot go
/// out of sync with the grades (and re-imported data gives the same numbers).
///
/// Sample terms (isDemo) are left out so example data never passes for real
/// results; [excludedSampleTerms] says how many were skipped.
class AcademicAnalytics {
  AcademicAnalytics._({
    required this.terms,
    required this.cumulativePercent,
    required this.cumulativeGrade,
    required this.totalUnits,
    required this.gradedUnits,
    required this.subjectCount,
    required this.gradedSubjectCount,
    required this.assessmentCount,
    required this.subjects,
    required this.target,
    required this.attention,
    required this.attentionTotal,
    required this.excludedSampleTerms,
  });

  /// Assessments scoring below this % are flagged as needing attention.
  static const double attentionBelow = GradeScales.passingPercent;

  final List<TermStat> terms;
  final double? cumulativePercent;
  final double? cumulativeGrade;
  final int totalUnits;
  final int gradedUnits;
  final int subjectCount;
  final int gradedSubjectCount;
  final int assessmentCount;

  /// Graded subjects, best first.
  final List<SubjectStat> subjects;
  final TargetProgress? target;
  final List<AttentionItem> attention;
  final int attentionTotal;
  final int excludedSampleTerms;

  bool get hasData => cumulativePercent != null;

  /// The most recent term in the user's list (what "current term" means here).
  TermStat? get currentTerm => terms.isEmpty ? null : terms.last;

  /// Terms that have a result, in the order the user keeps them.
  List<TermStat> get trend => terms.where((t) => t.percent != null).toList();

  bool get hasTrend => trend.length >= 2;

  /// Change in % from the previous graded term to the latest one.
  double? get trendDelta {
    final t = trend;
    if (t.length < 2) return null;
    return t.last.percent! - t[t.length - 2].percent!;
  }

  SubjectStat? get strongest => subjects.isEmpty ? null : subjects.first;

  /// Only meaningful with two or more graded subjects.
  SubjectStat? get lowest => subjects.length < 2 ? null : subjects.last;

  static AcademicAnalytics compute(
    List<AcademicTerm> allTerms,
    AppSettings settings,
  ) {
    final real = allTerms.where((t) => !t.isDemo).toList();
    final scale = settings.gpaScale;
    final allCourses = real.expand((t) => t.courses).toList();

    final termStats = real.map((t) {
      return TermStat(
        name: t.name,
        subjects: t.courses.length,
        gradedSubjects: t.courses.where((c) => c.hasGrades).length,
        units: GradeMath.totalUnits(t.courses),
        gradedUnits: GradeMath.gradedUnits(t.courses),
        percent: GradeMath.weightedPercent(t.courses),
        grade: GradeMath.weightedGrade(t.courses, scale, settings),
      );
    }).toList();

    final subjects = <SubjectStat>[];
    for (final t in real) {
      for (final c in t.courses) {
        final p = c.percent;
        if (p == null) continue;
        subjects.add(SubjectStat(
          termName: t.name,
          code: c.code,
          title: c.title,
          units: c.units,
          percent: p,
          assessments: c.assessments.length,
        ));
      }
    }
    subjects.sort((a, b) => b.percent.compareTo(a.percent));

    final cumulative = GradeMath.weightedPercent(allCourses);
    final targetPct = settings.targetPercent;

    // ---- attention list ------------------------------------------------
    final items = <AttentionItem>[];
    final low = <MapEntry<double, AttentionItem>>[];
    for (final t in real) {
      for (final c in t.courses) {
        if (!c.hasGrades) {
          items.add(AttentionItem(
            AttentionKind.noGrades,
            '${c.code} has no assessments yet',
            '${t.name}: add scores so it counts toward your results.',
          ));
          continue;
        }
        for (final a in c.assessments) {
          if (a.maxScore > 0 && a.scoreAchieved > a.maxScore) {
            items.add(AttentionItem(
              AttentionKind.overMax,
              '${a.title} (${c.code}) is above its maximum',
              'Score ${_n(a.scoreAchieved)} / ${_n(a.maxScore)}. Check the maximum score.',
            ));
          } else if (a.maxScore > 0 && a.percentage < attentionBelow) {
            low.add(MapEntry(
              a.percentage,
              AttentionItem(
                AttentionKind.lowScore,
                '${a.title} (${c.code}): ${a.percentage.toStringAsFixed(1)}%',
                '${a.category} in ${t.name}, below ${_n(attentionBelow)}%.',
              ),
            ));
          }
        }
        if (targetPct != null && c.percent! + 1e-9 < targetPct) {
          low.add(MapEntry(
            c.percent! + 1000, // after individual low scores
            AttentionItem(
              AttentionKind.belowTarget,
              '${c.code} is below your target',
              '${c.percent!.toStringAsFixed(1)}% vs target ${_n(targetPct)}%.',
            ),
          ));
        }
      }
    }
    low.sort((a, b) => a.key.compareTo(b.key));
    final all = [...low.map((e) => e.value), ...items];

    return AcademicAnalytics._(
      terms: termStats,
      cumulativePercent: cumulative,
      cumulativeGrade: GradeMath.weightedGrade(allCourses, scale, settings),
      totalUnits: GradeMath.totalUnits(allCourses),
      gradedUnits: GradeMath.gradedUnits(allCourses),
      subjectCount: allCourses.length,
      gradedSubjectCount: allCourses.where((c) => c.hasGrades).length,
      assessmentCount: allCourses.fold<int>(0, (n, c) => n + c.assessments.length),
      subjects: subjects,
      target: targetPct == null
          ? null
          : TargetProgress(targetPercent: targetPct, currentPercent: cumulative),
      attention: all.take(8).toList(),
      attentionTotal: all.length,
      excludedSampleTerms: allTerms.length - real.length,
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
