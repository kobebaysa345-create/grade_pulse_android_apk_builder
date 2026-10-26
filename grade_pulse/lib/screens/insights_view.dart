import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/analytics.dart';
import '../services/grade_math.dart';
import '../theme/app_theme.dart';

/// Academic insights, drawn entirely from [AcademicAnalytics] (which is
/// calculated from the saved records). Charts use plain Flutter widgets and
/// theme colours, so no chart package is needed.
class InsightsView extends StatelessWidget {
  const InsightsView({
    super.key,
    required this.stats,
    required this.settings,
    required this.onEditTarget,
  });

  final AcademicAnalytics stats;
  final AppSettings settings;
  final VoidCallback onEditTarget;

  String _grade(double? percent) => percent == null
      ? '—'
      : GradeScales.formatPercentOnActiveScale(percent, settings);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!stats.hasData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            context,
            child: Column(
              children: [
                Icon(Icons.insights_outlined, size: 34, color: cs.onSurfaceVariant),
                const SizedBox(height: 10),
                Text(
                  'Not enough data for insights yet',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  stats.subjectCount > 0
                      ? 'Add at least one assessment with a score to a subject to see averages, trends and strengths.'
                      : 'Add a term, a subject and at least one assessment with a score. Insights are calculated only from your own saved records.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          _targetCard(context),
          ..._footer(context),
        ],
      );
    }

    final current = stats.currentTerm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryTiles(context, current),
        _targetCard(context),
        _subjectsCard(context),
        _trendCard(context),
        _extremesCard(context),
        _attentionCard(context),
        ..._footer(context),
      ],
    );
  }

  // ---- building blocks -------------------------------------------------

  Widget _card(BuildContext context, {required Widget child}) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _heading(BuildContext context, String text, {Widget? trailing}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String label,
    String value, {
    String? sub,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            if (sub != null)
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTiles(BuildContext context, TermStat? current) {
    final scale = settings.gpaScale;
    final prefix = GradeScales.prefix(scale).toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              _tile(
                context,
                'CUMULATIVE $prefix',
                stats.cumulativeGrade == null
                    ? '—'
                    : GradeScales.formatGrade(stats.cumulativeGrade!, scale),
                sub: stats.cumulativePercent == null
                    ? null
                    : '${stats.cumulativePercent!.toStringAsFixed(1)}% average, unit-weighted',
              ),
              const SizedBox(width: 10),
              _tile(
                context,
                'CURRENT TERM',
                current?.grade == null
                    ? '—'
                    : GradeScales.formatGrade(current!.grade!, scale),
                sub: current == null
                    ? 'No terms'
                    : current.percent == null
                        ? '${current.name}: no grades yet'
                        : '${current.name} · ${current.percent!.toStringAsFixed(1)}%',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _tile(
                context,
                'TOTAL UNITS',
                '${stats.totalUnits}',
                sub: '${stats.gradedUnits} with recorded grades',
              ),
              const SizedBox(width: 10),
              _tile(
                context,
                'SUBJECTS',
                '${stats.subjectCount}',
                sub: '${stats.gradedSubjectCount} graded · ${stats.assessmentCount} assessments',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _targetCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final t = stats.target;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            context,
            'PROGRESS TOWARD YOUR TARGET',
            trailing: TextButton(
              onPressed: onEditTarget,
              child: Text(t == null ? 'Set target' : 'Change'),
            ),
          ),
          if (t == null)
            Text(
              'Set the overall average you are aiming for to see how far along you are.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: t.fraction,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerHighest,
                color: t.reached ? colors.success : cs.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.currentPercent == null
                  ? 'Target: ${_n(t.targetPercent)}% (${_grade(t.targetPercent)}). Add graded assessments to track progress.'
                  : t.reached
                      ? 'Target reached: ${t.currentPercent!.toStringAsFixed(1)}% vs ${_n(t.targetPercent)}% (${_grade(t.targetPercent)}).'
                      : '${t.currentPercent!.toStringAsFixed(1)}% of your ${_n(t.targetPercent)}% target (${_grade(t.targetPercent)}) — ${t.gap!.toStringAsFixed(1)} points to go.',
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Color _barColor(BuildContext context, double percent) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    if (percent >= 90) return colors.success;
    if (percent >= GradeScales.passingPercent) return cs.primary;
    return colors.warning;
  }

  Widget _subjectsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const maxRows = 12;
    final shown = stats.subjects.take(maxRows).toList();
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'SUBJECT PERFORMANCE'),
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                label:
                    '${s.code} ${s.title}, ${s.percent.toStringAsFixed(1)} percent',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${s.code} · ${s.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${s.percent.toStringAsFixed(1)}%  ·  ${_grade(s.percent)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (s.percent / 100).clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: _barColor(context, s.percent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (stats.subjects.length > maxRows)
            Text(
              '+ ${stats.subjects.length - maxRows} more subjects',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          Text(
            'Bars show each subject\'s average %. Green is 90+, purple 75+, amber below 75.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _trendCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final points = stats.trend;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'GRADE TREND ACROSS TERMS'),
          if (!stats.hasTrend)
            Text(
              'A trend appears once at least two terms have graded subjects. '
              'Terms are compared in the order they appear in your list.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            )
          else ...[
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendPainter(
                  values: points.map((p) => p.percent!).toList(),
                  line: cs.primary,
                  grid: cs.outlineVariant,
                  text: cs.onSurfaceVariant,
                  dot: cs.primary,
                  surface: cs.surface,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final p in points)
                  Expanded(
                    child: Text(
                      p.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final d = stats.trendDelta!;
              final up = d >= 0;
              return Row(
                children: [
                  Icon(
                    up ? Icons.trending_up : Icons.trending_down,
                    size: 18,
                    color: up ? colors.success : colors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${up ? 'Up' : 'Down'} ${d.abs().toStringAsFixed(1)} points from the previous term.',
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _extremesCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final best = stats.strongest;
    final worst = stats.lowest;

    Widget line(IconData icon, Color color, String label, SubjectStat? s, String empty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    s == null
                        ? empty
                        : '${s.code} · ${s.title}  —  ${s.percent.toStringAsFixed(1)}% (${_grade(s.percent)})',
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'STRONGEST AND LOWEST SUBJECTS'),
          line(Icons.emoji_events_outlined, colors.success, 'STRONGEST', best, '—'),
          line(
            Icons.flag_outlined,
            colors.warning,
            'LOWEST',
            worst,
            'Needs two graded subjects to compare.',
          ),
        ],
      ),
    );
  }

  Widget _attentionCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    IconData icon(AttentionKind k) {
      switch (k) {
        case AttentionKind.lowScore:
          return Icons.warning_amber_rounded;
        case AttentionKind.overMax:
          return Icons.error_outline;
        case AttentionKind.noGrades:
          return Icons.pending_outlined;
        case AttentionKind.belowTarget:
          return Icons.track_changes_outlined;
      }
    }

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'NEEDS ATTENTION'),
          if (stats.attention.isEmpty)
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: colors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nothing needs attention: no assessment is below '
                    '${_n(AcademicAnalytics.attentionBelow)}%.',
                    style: TextStyle(fontSize: 13, color: cs.onSurface),
                  ),
                ),
              ],
            )
          else ...[
            for (final item in stats.attention)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon(item.kind),
                      size: 18,
                      color: item.kind == AttentionKind.overMax ? cs.error : colors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            item.detail,
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (stats.attentionTotal > stats.attention.length)
              Text(
                '+ ${stats.attentionTotal - stats.attention.length} more',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _footer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return [
      if (stats.excludedSampleTerms > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${stats.excludedSampleTerms} sample term(s) are not counted here. '
            'Insights use only your own records.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      Text(
        'Calculated from your saved terms, subjects and assessments, weighted '
        'by units. ${GradeScales.describeActive(settings)}',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    ];
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Simple line chart: one point per term, evenly spaced, with value labels.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.text,
    required this.dot,
    required this.surface,
  });

  final List<double> values;
  final Color line;
  final Color grid;
  final Color text;
  final Color dot;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b) - 5;
    var hi = values.reduce((a, b) => a > b ? a : b) + 5;
    if (lo < 0) lo = 0;
    if (hi > 100) hi = 100;
    if (hi - lo < 10) {
      lo = (hi - 10).clamp(0.0, 100.0).toDouble();
      hi = lo + 10;
    }
    const topPad = 18.0;
    const bottomPad = 6.0;
    final h = size.height - topPad - bottomPad;
    double yOf(double v) => topPad + h * (1 - (v - lo) / (hi - lo));
    double xOf(int i) => size.width * (i + 0.5) / values.length;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [lo, hi]) {
      canvas.drawLine(Offset(0, yOf(v)), Offset(size.width, yOf(v)), gridPaint);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(xOf(i), yOf(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < values.length; i++) {
      final p = Offset(xOf(i), yOf(values[i]));
      canvas.drawCircle(p, 5, Paint()..color = surface);
      canvas.drawCircle(p, 4, Paint()..color = dot);
      final tp = TextPainter(
        text: TextSpan(
          text: '${values[i].toStringAsFixed(1)}%',
          style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (p.dx - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble();
      tp.paint(canvas, Offset(dx, (p.dy - 18).clamp(0.0, size.height).toDouble()));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values.length != values.length ||
      !_sameValues(old.values, values) ||
      old.line != line ||
      old.grid != grid ||
      old.text != text;

  static bool _sameValues(List<double> a, List<double> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
