import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/data_codec.dart';
import '../services/data_transfer.dart';

/// The user's decision from the import preview.
class ImportChoice {
  const ImportChoice(this.mode, this.outcome);
  final ImportMode mode;
  final ImportOutcome outcome;
}

/// Shows what a file contains and asks how to import it. Returns null if the
/// user cancels. Nothing is saved or changed by this dialog.
Future<ImportChoice?> showImportPreviewDialog(
  BuildContext context, {
  required String sourceLabel,
  required ParsedUserData parsed,
  required UserData current,
  ImportMode initialMode = ImportMode.merge,
}) {
  return showDialog<ImportChoice>(
    context: context,
    builder: (_) => _ImportPreviewDialog(
      sourceLabel: sourceLabel,
      parsed: parsed,
      current: current,
      initialMode: initialMode,
    ),
  );
}

/// Shows a readable error for a failed import/export.
Future<void> showDataErrorDialog(
  BuildContext context, {
  required String title,
  required Object error,
}) {
  final String message;
  final List<String> problems;
  if (error is JsonDataException) {
    message = error.message;
    problems = error.problems;
  } else {
    message = 'Something went wrong: $error';
    problems = const <String>[];
  }
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.error_outline, color: Theme.of(ctx).colorScheme.error),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final p in problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $p', style: const TextStyle(fontSize: 12)),
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Your existing data was not changed.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String describeCounts(DataCounts c) {
  final parts = <String>[
    if (c.terms > 0) '${c.terms} term${c.terms == 1 ? '' : 's'}',
    if (c.subjects > 0) '${c.subjects} subject${c.subjects == 1 ? '' : 's'}',
    if (c.assessments > 0)
      '${c.assessments} assessment${c.assessments == 1 ? '' : 's'}',
    if (c.reminders > 0)
      '${c.reminders} reminder${c.reminders == 1 ? '' : 's'}',
    if (c.groups > 0) '${c.groups} group${c.groups == 1 ? '' : 's'}',
    if (c.hasProfile) 'academic profile',
  ];
  return parts.isEmpty ? 'no records' : parts.join(', ');
}

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.sourceLabel,
    required this.parsed,
    required this.current,
    required this.initialMode,
  });

  final String sourceLabel;
  final ParsedUserData parsed;
  final UserData current;
  final ImportMode initialMode;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late ImportMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  Widget _row(String label, String value, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = widget.parsed;
    final incoming = DataCounts.of(parsed.data);
    final existing = DataCounts.of(widget.current);
    final outcome = DataTransfer.apply(_mode, widget.current, parsed.data);
    final isReplace = _mode == ImportMode.replace;

    return AlertDialog(
      title: const Text('Import preview'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.sourceLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                parsed.wasMigrated
                    ? 'Schema version ${parsed.sourceVersion} (upgraded to ${UserDataCodec.currentVersion})'
                    : 'Schema version ${parsed.sourceVersion}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Text(
                'IN THIS FILE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              _row('Academic terms', '${incoming.terms}', cs),
              _row('Subjects', '${incoming.subjects}', cs),
              _row('Assessments', '${incoming.assessments}', cs),
              _row('Reminders', '${incoming.reminders}', cs),
              _row('Study groups', '${incoming.groups}', cs),
              _row(
                'Settings (theme, GPA scale, calculator)',
                parsed.hasSettings ? 'Included' : 'None',
                cs,
              ),
              const SizedBox(height: 10),
              Text(
                'Currently in this account: ${describeCounts(existing)}.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ImportMode>(
                  segments: const [
                    ButtonSegment(
                      value: ImportMode.merge,
                      icon: Icon(Icons.merge_type),
                      label: Text('Merge'),
                    ),
                    ButtonSegment(
                      value: ImportMode.replace,
                      icon: Icon(Icons.swap_horiz),
                      label: Text('Replace'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              const SizedBox(height: 8),
              if (isReplace)
                Text(
                  'Replace deletes everything currently in this account '
                  '(${describeCounts(existing)}) and puts the file\'s '
                  'contents${parsed.hasSettings ? ', settings' : ''} and profile metadata in its place.',
                  style: TextStyle(color: cs.error, fontSize: 13),
                )
              else
                Text(
                  'Merge keeps all your current records, settings, and profile metadata and adds '
                  'only what is missing: ${describeCounts(outcome.added)}.'
                  '${outcome.skippedDuplicates > 0 ? ' ${outcome.skippedDuplicates} identical item(s) will be skipped.' : ''}'
                  '${outcome.keptBoth > 0 ? ' ${outcome.keptBoth} item(s) that share an ID with a different existing item will be added as separate copies.' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              if (parsed.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${parsed.warnings.length} note(s) about this file',
                    style: const TextStyle(fontSize: 13),
                  ),
                  children: [
                    for (final w in parsed.warnings)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $w', style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: isReplace
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, ImportChoice(_mode, outcome)),
          child: Text(isReplace ? 'Replace data' : 'Merge data'),
        ),
      ],
    );
  }
}
