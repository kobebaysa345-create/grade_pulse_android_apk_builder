import '../models/models.dart';

/// Grade conversion tables, formatting and unit-weighted aggregation.
///
/// IMPORTANT: the built-in tables below are generic defaults, NOT official
/// rules of TUP, PLM or any other school (no official TUP table could be
/// verified). Users can edit each table in Settings; edited tables are saved
/// in `settings.gradeBands` and are used for every grade shown in the app.
class GradeScales {
  const GradeScales._();

  static const String gpa = 'Standard 4.0 GPA';
  static const String percentage = 'Percentage %';
  static const String tup = 'TUP / PLM (1.0 - 5.0)';

  static const double passingPercent = 75;

  static const List<GradeBand> _gpaDefault = [
    GradeBand(93, 4.0),
    GradeBand(90, 3.7),
    GradeBand(87, 3.3),
    GradeBand(83, 3.0),
    GradeBand(80, 2.7),
    GradeBand(77, 2.3),
    GradeBand(73, 2.0),
    GradeBand(70, 1.7),
    GradeBand(67, 1.3),
    GradeBand(65, 1.0),
    GradeBand(0, 0.0),
  ];

  static const List<GradeBand> _tupDefault = [
    GradeBand(98, 1.00),
    GradeBand(95, 1.25),
    GradeBand(92, 1.50),
    GradeBand(89, 1.75),
    GradeBand(86, 2.00),
    GradeBand(83, 2.25),
    GradeBand(80, 2.50),
    GradeBand(77, 2.75),
    GradeBand(75, 3.00),
    GradeBand(0, 5.00),
  ];

  /// True for scales that use a conversion table (everything but Percentage).
  static bool usesTable(String scale) => scale != percentage;

  /// True when a bigger number is a better grade.
  static bool higherIsBetter(String scale) => scale != tup;

  static List<GradeBand> defaultBands(String scale) {
    switch (scale) {
      case gpa:
        return List<GradeBand>.of(_gpaDefault);
      case tup:
        return List<GradeBand>.of(_tupDefault);
      default:
        return const <GradeBand>[];
    }
  }

  static bool isCustomised(AppSettings s, String scale) =>
      (s.gradeBands[scale] ?? const <GradeBand>[]).isNotEmpty;

  /// The table in use for [scale]: the user's own if saved, else the default.
  /// Always sorted from the highest minimum percentage down.
  static List<GradeBand> bandsFor(AppSettings s, String scale) {
    final custom = s.gradeBands[scale];
    final bands = (custom != null && custom.isNotEmpty)
        ? List<GradeBand>.of(custom)
        : defaultBands(scale);
    bands.sort((a, b) => b.minPercent.compareTo(a.minPercent));
    return bands;
  }

  /// The grade that [percent] earns on [scale]. For the Percentage scale this
  /// is the percentage itself.
  static double convert(double percent, String scale, AppSettings s) {
    if (!usesTable(scale)) return percent;
    final bands = bandsFor(s, scale);
    for (final b in bands) {
      if (percent + 1e-9 >= b.minPercent) return b.grade;
    }
    return bands.isEmpty ? percent : bands.last.grade;
  }

  /// Text for a value that is already on [scale].
  static String formatGrade(double grade, String scale) {
    if (scale == percentage) return '${grade.toStringAsFixed(1)}%';
    return grade.toStringAsFixed(2);
  }

  /// Text for a percentage, shown on the user's active scale.
  static String formatPercentOnActiveScale(double percent, AppSettings s) =>
      formatGrade(convert(percent, s.gpaScale, s), s.gpaScale);

  /// Short label for the kind of number the active scale produces.
  static String prefix(String scale) {
    switch (scale) {
      case percentage:
        return 'Average';
      case tup:
        return 'Grade';
      default:
        return 'GPA';
    }
  }

  /// One line that identifies the active scale and where its table comes from.
  static String describeActive(AppSettings s) {
    if (!usesTable(s.gpaScale)) {
      return 'Scale: Percentage % (no conversion table).';
    }
    final source = isCustomised(s, s.gpaScale)
        ? 'your edited table'
        : 'built-in default table, not an official school rule';
    return 'Scale: ${s.gpaScale} using $source. Edit it in Settings.';
  }

  /// Checks an edited table. Returns an error message, or null if valid.
  static String? validateBands(List<GradeBand> bands) {
    if (bands.isEmpty) return 'Add at least one row.';
    if (bands.length > 20) return 'Use 20 rows or fewer.';
    final mins = <double>{};
    for (final b in bands) {
      if (!b.minPercent.isFinite || b.minPercent < 0 || b.minPercent > 100) {
        return 'Each minimum % must be between 0 and 100.';
      }
      if (!b.grade.isFinite || b.grade < 0) {
        return 'Each grade must be a number of 0 or more.';
      }
      if (!mins.add(b.minPercent)) return 'Two rows share the same minimum %.';
    }
    if (!mins.contains(0.0)) {
      return 'The lowest row must start at 0% so every score has a grade.';
    }
    return null;
  }
}

/// Unit-weighted results over a set of subjects.
class GradeMath {
  const GradeMath._();

  /// Subjects that count toward results: they have at least one assessment and
  /// a positive number of units.
  static Iterable<Course> _counted(Iterable<Course> courses) =>
      courses.where((c) => c.hasGrades && c.units > 0);

  static int gradedUnits(Iterable<Course> courses) =>
      _counted(courses).fold<int>(0, (n, c) => n + c.units);

  static int totalUnits(Iterable<Course> courses) =>
      courses.fold<int>(0, (n, c) => n + c.units);

  /// Unit-weighted mean of subject percentages, or null if nothing is graded.
  static double? weightedPercent(Iterable<Course> courses) {
    var points = 0.0;
    var units = 0;
    for (final c in _counted(courses)) {
      points += c.averagePercentage * c.units;
      units += c.units;
    }
    return units == 0 ? null : points / units;
  }

  /// Unit-weighted mean of the grade each subject earns on [scale]. Each
  /// subject is converted first, then averaged (the usual way GPA is built),
  /// instead of converting the overall percentage.
  static double? weightedGrade(
    Iterable<Course> courses,
    String scale,
    AppSettings s,
  ) {
    if (!GradeScales.usesTable(scale)) return weightedPercent(courses);
    var points = 0.0;
    var units = 0;
    for (final c in _counted(courses)) {
      points += GradeScales.convert(c.averagePercentage, scale, s) * c.units;
      units += c.units;
    }
    return units == 0 ? null : points / units;
  }
}

enum CalcStatus {
  /// Some inputs are still empty.
  incomplete,

  /// An input is not a valid number or the weights do not add up.
  invalid,

  /// The target can be reached with a score between 0 and 100 on the rest.
  achievable,

  /// The target is already secured, even with 0% on the remaining work.
  secured,

  /// The target cannot be reached, even with 100% on the remaining work.
  impossible,
}

class CalcResult {
  const CalcResult._(
    this.status,
    this.message, {
    this.requiredScore,
    this.maxPossible,
    this.lowestPossible,
    this.completedWeight,
    this.remainingWeight,
    this.current,
  });

  final CalcStatus status;

  /// Plain-language explanation shown under the result.
  final String message;

  /// Score needed on the remaining work, in %. Not clamped, so an impossible
  /// target shows the real figure (e.g. 112.5). Null when it cannot be computed.
  final double? requiredScore;

  /// The best (all remaining work at 100%) and worst (all at 0%) final result.
  final double? maxPossible;
  final double? lowestPossible;

  /// Weights as percentages, after validation.
  final double? completedWeight;
  final double? remainingWeight;
  final double? current;

  bool get isValid =>
      status == CalcStatus.achievable ||
      status == CalcStatus.secured ||
      status == CalcStatus.impossible;

  /// Final grade (%) if the remaining work averages [remainingScore] percent.
  double? projectedFinal(double remainingScore) {
    if (!isValid || current == null) return null;
    return current! * (completedWeight! / 100) +
        remainingScore * (remainingWeight! / 100);
  }
}

class GradeCalculator {
  const GradeCalculator._();

  /// Parses a user-typed number. Accepts a trailing %, spaces and a decimal
  /// comma. Returns null for blank, non-numeric, NaN or infinite input.
  static double? parse(String raw) {
    var t = raw.trim().replaceAll('%', '').trim();
    if (t.isEmpty) return null;
    if (t.contains(',') && !t.contains('.')) t = t.replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null || !v.isFinite) return null;
    return v;
  }

  static CalcResult _invalid(String message) =>
      CalcResult._(CalcStatus.invalid, message);

  /// Required remaining score =
  ///   (target - current x completedWeight) / remainingWeight
  /// with the weights as fractions between 0 and 1 and the grades in %.
  ///
  /// All arguments are the raw text from the input fields. [remaining] may be
  /// blank, in which case it is 100 - [completed].
  static CalcResult solve({
    required String current,
    required String completed,
    String remaining = '',
    required String target,
  }) {
    final missing = <String>[
      if (current.trim().isEmpty) 'current average',
      if (completed.trim().isEmpty) 'completed weight',
      if (target.trim().isEmpty) 'target',
    ];
    if (missing.isNotEmpty) {
      return CalcResult._(
        CalcStatus.incomplete,
        'Enter your ${missing.join(', ')} to see the result.',
      );
    }

    final cur = parse(current);
    final cw = parse(completed);
    final tgt = parse(target);
    final rem = remaining.trim().isEmpty ? null : parse(remaining);

    if (cur == null) return _invalid('Current average must be a number.');
    if (cw == null) return _invalid('Completed weight must be a number.');
    if (tgt == null) return _invalid('Target must be a number.');
    if (remaining.trim().isNotEmpty && rem == null) {
      return _invalid('Remaining weight must be a number.');
    }

    if (cur < 0 || cur > 100) {
      return _invalid('Current average must be between 0% and 100%.');
    }
    if (cw < 0 || cw > 100) {
      return _invalid('Completed weight must be between 0% and 100%.');
    }
    if (tgt < 0 || tgt > 100) {
      return _invalid('Target must be between 0% and 100%.');
    }
    if (rem != null && (rem < 0 || rem > 100)) {
      return _invalid('Remaining weight must be between 0% and 100%.');
    }
    if (rem != null && (cw + rem - 100).abs() > 0.005) {
      return _invalid(
        'Completed (${_n(cw)}%) and remaining (${_n(rem)}%) weight must add up '
        'to 100%, but they add up to ${_n(cw + rem)}%.',
      );
    }

    final remainingPct = rem ?? (100 - cw);
    final wc = cw / 100; // fraction
    final wr = remainingPct / 100; // fraction
    final lowest = cur * wc;
    final best = cur * wc + 100 * wr;

    // Completed weight is 100%: nothing left to earn, so no division.
    if (wr <= 1e-9) {
      final reached = cur + 1e-9 >= tgt;
      return CalcResult._(
        reached ? CalcStatus.secured : CalcStatus.impossible,
        reached
            ? 'All the weight is completed. Your final result is ${_n(cur)}%, '
                'which meets your target of ${_n(tgt)}%.'
            : 'All the weight is completed. Your final result is ${_n(cur)}%, '
                'which is below your target of ${_n(tgt)}%. Nothing remains that '
                'could raise it.',
        requiredScore: null,
        maxPossible: cur,
        lowestPossible: cur,
        completedWeight: cw,
        remainingWeight: 0,
        current: cur,
      );
    }

    final needed = (tgt - cur * wc) / wr;

    if (needed > 100 + 1e-9) {
      return CalcResult._(
        CalcStatus.impossible,
        'Not achievable. You would need ${_n(needed)}% on the remaining '
        '${_n(remainingPct)}%, but the most you can score is 100%. Even a '
        'perfect score gives a final result of ${_n(best)}%.',
        requiredScore: needed,
        maxPossible: best,
        lowestPossible: lowest,
        completedWeight: cw,
        remainingWeight: remainingPct,
        current: cur,
      );
    }
    if (needed <= 1e-9) {
      return CalcResult._(
        CalcStatus.secured,
        'Target secured. Even with 0% on the remaining ${_n(remainingPct)}%, '
        'your final result is at least ${_n(lowest)}%.',
        requiredScore: 0,
        maxPossible: best,
        lowestPossible: lowest,
        completedWeight: cw,
        remainingWeight: remainingPct,
        current: cur,
      );
    }
    return CalcResult._(
      CalcStatus.achievable,
      'Achievable. Average at least ${_n(needed)}% on the remaining '
      '${_n(remainingPct)}% to finish at ${_n(tgt)}%.',
      requiredScore: needed,
      maxPossible: best,
      lowestPossible: lowest,
      completedWeight: cw,
      remainingWeight: remainingPct,
      current: cur,
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
