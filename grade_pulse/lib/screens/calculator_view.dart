import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/weighted_grade_calculator.dart';
import '../theme/app_theme.dart';

/// Weighted academic grade calculator. Scores are stored in the existing
/// per-user settings and saved through [onChanged] as they are edited.
class CalculatorView extends StatefulWidget {
  const CalculatorView({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /// Edited in place; the owner saves it when [onChanged] fires.
  final AppSettings settings;
  final VoidCallback onChanged;

  @override
  State<CalculatorView> createState() => _CalculatorViewState();
}

class _CalculatorViewState extends State<CalculatorView> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final component in WeightedGradeCalculator.components)
        component.id: TextEditingController(text: _savedScore(component.id)),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _savedScore(String id) => switch (id) {
    'quiz' => widget.settings.calcQuiz,
    'recitation' => widget.settings.calcRecitation,
    'groupActivities' => widget.settings.calcGroupActivities,
    'selfCheck' => widget.settings.calcSelfCheck,
    'unitTest1' => widget.settings.calcUnitTest1,
    'unitTest2' => widget.settings.calcUnitTest2,
    'termTest' => widget.settings.calcTermTest,
    _ => '',
  };

  void _saveScore(String id, String value) {
    switch (id) {
      case 'quiz':
        widget.settings.calcQuiz = value;
        break;
      case 'recitation':
        widget.settings.calcRecitation = value;
        break;
      case 'groupActivities':
        widget.settings.calcGroupActivities = value;
        break;
      case 'selfCheck':
        widget.settings.calcSelfCheck = value;
        break;
      case 'unitTest1':
        widget.settings.calcUnitTest1 = value;
        break;
      case 'unitTest2':
        widget.settings.calcUnitTest2 = value;
        break;
      case 'termTest':
        widget.settings.calcTermTest = value;
        break;
    }
  }

  void _onScoreChanged(WeightedGradeComponent component, String value) {
    _saveScore(component.id, value);
    setState(() {});
    widget.onChanged();
  }

  void _clear() {
    for (final component in WeightedGradeCalculator.components) {
      _controllers[component.id]!.clear();
      _saveScore(component.id, '');
    }
    FocusScope.of(context).unfocus();
    setState(() {});
    widget.onChanged();
  }

  String? _validationMessage(String raw) {
    if (raw.trim().isEmpty) return null;
    final score = double.tryParse(raw.trim());
    if (score == null || !score.isFinite) {
      return 'Enter a valid number from 0 to 100.';
    }
    if (score < 0 || score > 100) {
      return 'Score must be between 0 and 100.';
    }
    return null;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatContribution(double value) => value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  WeightedGradeResult? _calculateIfComplete() {
    final scores = <String, double>{};
    for (final component in WeightedGradeCalculator.components) {
      final raw = _controllers[component.id]!.text.trim();
      if (raw.isEmpty || _validationMessage(raw) != null) return null;
      final score = double.tryParse(raw);
      if (score == null) return null;
      scores[component.id] = score;
    }
    return WeightedGradeCalculator.calculate(scores);
  }

  Widget _scoreField(
    BuildContext context,
    WeightedGradeComponent component,
  ) {
    final cs = Theme.of(context).colorScheme;
    final controller = _controllers[component.id]!;
    final error = _validationMessage(controller.text);
    return TextField(
      key: ValueKey('weighted-score-${component.id}'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      onChanged: (value) => _onScoreChanged(component, value),
      decoration: InputDecoration(
        labelText: component.label,
        suffixText: '%',
        helperText: error == null
            ? 'Weight: ${_formatNumber(component.weightPercent)}%'
            : null,
        errorText: error,
        helperStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context,
    WeightedGradeSection section,
  ) {
    final cs = Theme.of(context).colorScheme;
    final components = WeightedGradeCalculator.components
        .where((component) => component.section == section)
        .toList();
    final weight = WeightedGradeCalculator.sectionWeightPercent(section);
    final subtitle = switch (section) {
      WeightedGradeSection.classActivities => 'Four activities · 7.5% each',
      WeightedGradeSection.unitTests => 'Each unit test contributes 20%',
      WeightedGradeSection.termTest => 'One final component · 30%',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        WeightedGradeCalculator.sectionLabel(section),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      '${_formatNumber(weight)}%',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 500 ? 2 : 1;
                final fieldWidth = columns == 2
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final component in components)
                      SizedBox(
                        width: fieldWidth,
                        child: _scoreField(context, component),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow(
    BuildContext context,
    WeightedGradeResult result,
    WeightedGradeComponent component,
  ) {
    final cs = Theme.of(context).colorScheme;
    final score = result.scoreFor(component);
    final contribution = result.contributionFor(component);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  component.label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Score ${_formatNumber(score)}%  ·  Weight ${_formatNumber(component.weightPercent)}%',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_formatContribution(contribution)}%',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallCard(
    BuildContext context, {
    required WeightedGradeResult? result,
    required bool hasInvalidScore,
  }) {
    final cs = Theme.of(context).colorScheme;
    final message = result != null
        ? 'Your weighted grade is calculated from all seven scores.'
        : hasInvalidScore
        ? 'Fix the highlighted scores to calculate your overall grade.'
        : 'Enter all scores to calculate your overall grade.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'OVERALL WEIGHTED GRADE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.6,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
              ),
              child: Column(
                children: [
                  Text(
                    result == null
                        ? '—'
                        : '${result.overallGrade.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: cs.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'COMPONENT BREAKDOWN',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    'WEIGHTED CONTRIBUTION',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final section in WeightedGradeSection.values) ...[
                if (section != WeightedGradeSection.classActivities)
                  const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${WeightedGradeCalculator.sectionLabel(section).toUpperCase()}  ·  ${_formatNumber(WeightedGradeCalculator.sectionWeightPercent(section))}%',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Subtotal ${result.subtotalFor(section).toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                for (final component in WeightedGradeCalculator.components.where(
                  (component) => component.section == section,
                ))
                  _breakdownRow(context, result, component),
              ],
              const SizedBox(height: 8),
              Divider(color: cs.outlineVariant),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total weighted grade',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${result.overallGrade.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasInvalidScore = WeightedGradeCalculator.components.any((component) {
      final raw = _controllers[component.id]!.text;
      return raw.trim().isNotEmpty && _validationMessage(raw) != null;
    });
    final result = hasInvalidScore ? null : _calculateIfComplete();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'WEIGHTED GRADE CALCULATOR',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('weighted-grade-reset'),
              onPressed: _clear,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final section in WeightedGradeSection.values) ...[
          _sectionCard(context, section),
          const SizedBox(height: 10),
        ],
        _overallCard(
          context,
          result: result,
          hasInvalidScore: hasInvalidScore,
        ),
      ],
    );
  }
}
