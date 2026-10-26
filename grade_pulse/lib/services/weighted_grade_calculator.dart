/// The seven independently weighted components used by the weighted-grade
/// calculator. Weights are percentages of the final course grade.
enum WeightedGradeSection { classActivities, unitTests, termTest }

class WeightedGradeComponent {
  const WeightedGradeComponent({
    required this.id,
    required this.label,
    required this.weightPercent,
    required this.section,
  });

  /// Stable ID used to persist this score in the user's settings.
  final String id;
  final String label;
  final double weightPercent;
  final WeightedGradeSection section;
}

/// Immutable output from a complete, validated weighted-grade calculation.
class WeightedGradeResult {
  WeightedGradeResult._({
    required Map<String, double> scores,
    required Map<String, double> contributions,
    required Map<WeightedGradeSection, double> sectionSubtotals,
    required this.overallGrade,
  }) : scores = Map<String, double>.unmodifiable(scores),
       contributions = Map<String, double>.unmodifiable(contributions),
       sectionSubtotals = Map<WeightedGradeSection, double>.unmodifiable(sectionSubtotals);

  final Map<String, double> scores;
  final Map<String, double> contributions;
  final Map<WeightedGradeSection, double> sectionSubtotals;
  final double overallGrade;

  double scoreFor(WeightedGradeComponent component) => scores[component.id]!;

  double contributionFor(WeightedGradeComponent component) =>
      contributions[component.id]!;

  double subtotalFor(WeightedGradeSection section) =>
      sectionSubtotals[section]!;
}

/// Centralized source of truth for the grading weights and calculation.
class WeightedGradeCalculator {
  const WeightedGradeCalculator._();

  static const List<WeightedGradeComponent> components = [
    WeightedGradeComponent(
      id: 'quiz',
      label: 'Quizzes',
      weightPercent: 7.5,
      section: WeightedGradeSection.classActivities,
    ),
    WeightedGradeComponent(
      id: 'recitation',
      label: 'Recitation',
      weightPercent: 7.5,
      section: WeightedGradeSection.classActivities,
    ),
    WeightedGradeComponent(
      id: 'groupActivities',
      label: 'Group Activities',
      weightPercent: 7.5,
      section: WeightedGradeSection.classActivities,
    ),
    WeightedGradeComponent(
      id: 'selfCheck',
      label: 'Self-Check',
      weightPercent: 7.5,
      section: WeightedGradeSection.classActivities,
    ),
    WeightedGradeComponent(
      id: 'unitTest1',
      label: 'Unit Test 1',
      weightPercent: 20,
      section: WeightedGradeSection.unitTests,
    ),
    WeightedGradeComponent(
      id: 'unitTest2',
      label: 'Unit Test 2',
      weightPercent: 20,
      section: WeightedGradeSection.unitTests,
    ),
    WeightedGradeComponent(
      id: 'termTest',
      label: 'Term Test',
      weightPercent: 30,
      section: WeightedGradeSection.termTest,
    ),
  ];

  static double get totalWeightPercent => components.fold<double>(
    0,
    (total, component) => total + component.weightPercent,
  );

  static String sectionLabel(WeightedGradeSection section) => switch (section) {
    WeightedGradeSection.classActivities => 'Class Activities',
    WeightedGradeSection.unitTests => 'Unit Tests',
    WeightedGradeSection.termTest => 'Term Test',
  };

  static double sectionWeightPercent(WeightedGradeSection section) =>
      components
          .where((component) => component.section == section)
          .fold<double>(0, (total, component) => total + component.weightPercent);

  /// Calculates contributions once, after confirming every required score is
  /// present and between 0 and 100 inclusive. Missing or invalid scores throw
  /// instead of silently being treated as zero.
  static WeightedGradeResult calculate(Map<String, double> scores) {
    final normalizedScores = <String, double>{};
    final contributions = <String, double>{};
    final subtotals = <WeightedGradeSection, double>{
      for (final section in WeightedGradeSection.values) section: 0,
    };

    for (final component in components) {
      final score = scores[component.id];
      if (score == null || !score.isFinite || score < 0 || score > 100) {
        throw ArgumentError.value(
          score,
          component.id,
          'Every score must be a number from 0 to 100.',
        );
      }
      normalizedScores[component.id] = score;

      final contribution = score * component.weightPercent / 100;
      contributions[component.id] = contribution;
      subtotals[component.section] = subtotals[component.section]! + contribution;
    }

    // The validated weights total exactly 100%, so a valid score set cannot
    // legitimately exceed 100. Clamp only to prevent floating-point drift.
    final total = contributions.values.fold<double>(0, (sum, value) => sum + value);
    final boundedTotal = total.clamp(0.0, 100.0).toDouble();

    return WeightedGradeResult._(
      scores: normalizedScores,
      contributions: contributions,
      sectionSubtotals: subtotals,
      overallGrade: boundedTotal,
    );
  }
}
