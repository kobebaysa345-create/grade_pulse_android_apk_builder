import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/data_codec.dart';
import '../services/data_transfer.dart';

/// A focused workspace for inspecting and editing the signed-in account's
/// serialized Grade Pulse data without exposing file import/export controls.
class AntigravityJsonView extends StatefulWidget {
  const AntigravityJsonView({
    super.key,
    required this.currentDataJson,
    required this.premadeSourcePath,
    required this.onApply,
    required this.onClose,
  });

  final String currentDataJson;
  final String premadeSourcePath;
  final Future<void> Function(String raw, ImportMode preferredMode) onApply;
  final VoidCallback onClose;

  @override
  State<AntigravityJsonView> createState() => _AntigravityJsonViewState();
}

class _AntigravityJsonViewState extends State<AntigravityJsonView> {
  late final TextEditingController _accountController;
  late final TextEditingController _premadeController;
  _EditorSource _selectedSource = _EditorSource.account;
  ParsedUserData? _parsed;
  String? _validationMessage;
  bool _premadeLoading = true;
  bool _applying = false;

  TextEditingController get _activeController =>
      _selectedSource == _EditorSource.account
          ? _accountController
          : _premadeController;

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController(text: widget.currentDataJson);
    _premadeController = TextEditingController();
    _validateSource();
    _loadPremadeSource();
  }

  @override
  void dispose() {
    _accountController.dispose();
    _premadeController.dispose();
    super.dispose();
  }

  Future<void> _loadPremadeSource() async {
    try {
      final content = await rootBundle.loadString(widget.premadeSourcePath);
      if (!mounted) return;
      setState(() {
        _premadeController.text = content;
        _premadeLoading = false;
        if (_selectedSource == _EditorSource.premade) _validateSource();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _premadeLoading = false;
        if (_selectedSource == _EditorSource.premade) {
          _parsed = null;
          _validationMessage = 'The bundled preset could not be loaded.';
        }
      });
    }
  }

  void _selectSource(_EditorSource source) {
    setState(() {
      _selectedSource = source;
      _validateSource();
    });
  }

  void _validateSource() {
    if (_selectedSource == _EditorSource.premade && _premadeLoading) {
      _parsed = null;
      _validationMessage = 'Loading the bundled preset…';
      return;
    }
    try {
      _parsed = UserDataCodec.parse(_activeController.text);
      _validationMessage = null;
    } on JsonDataException catch (error) {
      _parsed = null;
      _validationMessage = error.message;
    } catch (_) {
      _parsed = null;
      _validationMessage = 'The data could not be validated.';
    }
  }

  Future<void> _applyChanges() async {
    if (_parsed == null || _applying) return;
    setState(() => _applying = true);
    try {
      await widget.onApply(
        _activeController.text,
        _selectedSource == _EditorSource.account
            ? ImportMode.replace
            : ImportMode.merge,
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to Grade Pulse',
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ANTIGRAVITY',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Data workspace',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.data_object_rounded), text: 'JSON Management'),
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'Structure Preview'),
            ],
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _buildEditorTab(cs),
                _buildStructureTab(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedSource == _EditorSource.account
                      ? 'CURRENT ACCOUNT DATA'
                      : 'PREMADE SOURCE DATA',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose the current account data or the bundled preset, then '
                  'edit the document directly. The packaged asset itself stays '
                  'unchanged; applying edits saves your customized data to this '
                  'account after review.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SegmentedButton<_EditorSource>(
                  segments: const [
                    ButtonSegment(
                      value: _EditorSource.account,
                      icon: Icon(Icons.person_outline_rounded),
                      label: Text('Account data'),
                    ),
                    ButtonSegment(
                      value: _EditorSource.premade,
                      icon: Icon(Icons.dataset_outlined),
                      label: Text('Premade source'),
                    ),
                  ],
                  selected: {_selectedSource},
                  onSelectionChanged: (selection) => _selectSource(selection.first),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'Bundled preset path: ${widget.premadeSourcePath}',
                  key: const ValueKey('antigravity-source-path'),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('antigravity-json-editor'),
                  controller: _activeController,
                  onChanged: (_) => setState(_validateSource),
                  minLines: 16,
                  maxLines: 24,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Editable data structure',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: cs.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _parsed == null ? Icons.error_outline : Icons.check_circle_outline,
                      size: 18,
                      color: _parsed == null ? cs.error : cs.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _parsed == null
                            ? (_validationMessage ?? 'The data is invalid.')
                            : 'Valid Grade Pulse data. Changes are not saved until you review and apply them.',
                        style: TextStyle(
                          color: _parsed == null ? cs.error : cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('antigravity-apply-changes'),
                    onPressed: _parsed == null || _applying ? null : _applyChanges,
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_applying ? 'Applying…' : 'Review & apply changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStructureTab(ColorScheme cs) {
    final parsed = _parsed;
    if (parsed == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_object_outlined, size: 36, color: cs.error),
              const SizedBox(height: 10),
              Text(
                _validationMessage ?? 'Fix the data in JSON Management to preview its structure.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
            ],
          ),
        ),
      );
    }

    final counts = DataCounts.of(parsed.data);
    final rows = <(String, String)>[
      ('Schema version', '${parsed.sourceVersion}'),
      ('Academic terms', '${counts.terms}'),
      ('Subjects / courses', '${counts.subjects}'),
      ('Assessments', '${counts.assessments}'),
      ('Reminders', '${counts.reminders}'),
      ('Study groups', '${counts.groups}'),
      ('Academic profile', counts.hasProfile ? 'Configured' : 'Not configured'),
      ('Settings', parsed.hasSettings ? 'Included' : 'Default settings'),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DATA STRUCTURE',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This preview updates as you edit the data. The editor is validated against the same schema used by Grade Pulse when reading saved data.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 14),
                for (final row in rows) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.$1,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        row.$2,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (row != rows.last) const Divider(height: 18),
                ],
                if (parsed.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Validation notes',
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final warning in parsed.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '• $warning',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _EditorSource { account, premade }
