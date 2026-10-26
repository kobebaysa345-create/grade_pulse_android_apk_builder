import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/grade_math.dart';

/// Lets the user view and edit the grade conversion table of the 4.0 and
/// TUP / PLM scales. Returns the complete new `gradeBands` map to save, or
/// null if cancelled. A scale whose table equals the default is not stored.
Future<Map<String, List<GradeBand>>?> showGradeTableDialog(
  BuildContext context, {
  required AppSettings settings,
}) {
  return showDialog<Map<String, List<GradeBand>>>(
    context: context,
    builder: (_) => _GradeTableDialog(settings: settings),
  );
}

class _Row {
  _Row(double min, double grade)
    : min = TextEditingController(text: _fmt(min)),
      grade = TextEditingController(text: _fmtGrade(grade));
  final TextEditingController min;
  final TextEditingController grade;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  static String _fmtGrade(double v) => v.toStringAsFixed(2);

  void dispose() {
    min.dispose();
    grade.dispose();
  }
}

class _GradeTableDialog extends StatefulWidget {
  const _GradeTableDialog({required this.settings});
  final AppSettings settings;

  @override
  State<_GradeTableDialog> createState() => _GradeTableDialogState();
}

class _GradeTableDialogState extends State<_GradeTableDialog> {
  static const List<String> _scales = [GradeScales.gpa, GradeScales.tup];

  late String _scale;
  final Map<String, List<_Row>> _rows = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _scale = GradeScales.usesTable(widget.settings.gpaScale)
        ? widget.settings.gpaScale
        : GradeScales.gpa;
    for (final s in _scales) {
      _rows[s] = GradeScales.bandsFor(widget.settings, s)
          .map((b) => _Row(b.minPercent, b.grade))
          .toList();
    }
  }

  @override
  void dispose() {
    for (final list in _rows.values) {
      for (final r in list) {
        r.dispose();
      }
    }
    super.dispose();
  }

  /// Reads one scale's rows; returns null and sets [_error] if invalid.
  List<GradeBand>? _read(String scale) {
    final bands = <GradeBand>[];
    for (final r in _rows[scale]!) {
      final min = double.tryParse(r.min.text.trim().replaceAll(',', '.'));
      final grade = double.tryParse(r.grade.text.trim().replaceAll(',', '.'));
      if (min == null || grade == null) {
        _error = '${scale == GradeScales.gpa ? '4.0 GPA' : 'TUP / PLM'}: every row needs a number in both boxes.';
        return null;
      }
      bands.add(GradeBand(min, grade));
    }
    final error = GradeScales.validateBands(bands);
    if (error != null) {
      _error = '${scale == GradeScales.gpa ? '4.0 GPA' : 'TUP / PLM'}: $error';
      return null;
    }
    bands.sort((a, b) => b.minPercent.compareTo(a.minPercent));
    return bands;
  }

  bool _sameAsDefault(String scale, List<GradeBand> bands) {
    final d = GradeScales.defaultBands(scale);
    if (d.length != bands.length) return false;
    for (var i = 0; i < d.length; i++) {
      if (d[i].minPercent != bands[i].minPercent || d[i].grade != bands[i].grade) {
        return false;
      }
    }
    return true;
  }

  void _save() {
    final result = <String, List<GradeBand>>{};
    for (final s in _scales) {
      final bands = _read(s);
      if (bands == null) {
        setState(() {});
        return;
      }
      if (!_sameAsDefault(s, bands)) result[s] = bands;
    }
    Navigator.pop(context, result);
  }

  void _reset() {
    setState(() {
      for (final r in _rows[_scale]!) {
        r.dispose();
      }
      _rows[_scale] = GradeScales.defaultBands(_scale)
          .map((b) => _Row(b.minPercent, b.grade))
          .toList();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows[_scale]!;
    const keyboard = TextInputType.numberWithOptions(decimal: true);

    return AlertDialog(
      title: const Text('Grade conversion tables'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each row means: a score of at least this % earns this grade. '
                'The built-in tables are generic defaults, not official school '
                'rules, so match them to your school\'s grading policy.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: GradeScales.gpa, label: Text('4.0 GPA')),
                    ButtonSegment(value: GradeScales.tup, label: Text('TUP / PLM')),
                  ],
                  selected: {_scale},
                  onSelectionChanged: (s) => setState(() {
                    _scale = s.first;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rows[i].min,
                          keyboardType: keyboard,
                          decoration: const InputDecoration(
                            labelText: 'Min %',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rows[i].grade,
                          keyboardType: keyboard,
                          decoration: const InputDecoration(
                            labelText: 'Grade',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove row',
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: rows.length <= 1
                            ? null
                            : () => setState(() {
                                rows.removeAt(i).dispose();
                                _error = null;
                              }),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: rows.length >= 20
                        ? null
                        : () => setState(() => rows.add(_Row(0, 0))),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add row'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _reset,
                    child: const Text('Reset to default'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save tables')),
      ],
    );
  }
}
