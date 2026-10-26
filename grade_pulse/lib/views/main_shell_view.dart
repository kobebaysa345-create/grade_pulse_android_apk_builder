import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_data_provider.dart';
import '../providers/repository_providers.dart';
import '../repositories/user_data_repository.dart';
import 'academics_view.dart';
import 'study_groups_view.dart';
import 'calendar_view.dart';
import 'grade_calculator_view.dart';
import 'profile_view.dart';
import '../models/models.dart';
import '../services/analytics.dart';
import '../services/auth_service.dart';
import '../services/data_codec.dart';
import '../services/data_file_service.dart';
import '../services/data_transfer.dart';
import '../services/grade_math.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../screens/antigravity_json_view.dart';
import '../screens/calculator_view.dart';
import '../screens/data_transfer_dialogs.dart';
import '../screens/grade_table_dialog.dart';
import '../screens/insights_view.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({
    super.key,
    required this.controller,
    required this.user,
    this.files = const DeviceDataFileService(),
  });

  final AppController controller;
  final AppUser user;

  /// File chooser / save dialog (replaceable in tests).
  final DataFileService files;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

enum _SaveState { saving, saved, failed }

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  bool _showAntigravityTab = false;

  // Loading state
  bool _loading = true;
  bool _loaded = false;
  String? _loadError;

  // Calendar State
  String _calendarView = 'Month'; // 'Day', 'Week', 'Month', 'Year'
  DateTime _focusedDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  String _reminderCategoryFilter = 'All';
  String _reminderStatusFilter = 'All';
  bool _remindersOnly = false;
  String _groupSearch = '';

  // Editable domain data lives in userDataProvider. These accessors resolve
  // the current provider state rather than maintaining local model copies.
  final List<AcademicTerm> _emptyTerms = <AcademicTerm>[];
  final List<Reminder> _emptyReminders = <Reminder>[];
  final List<StudyGroup> _emptyGroups = <StudyGroup>[];
  final AppSettings _emptySettings = AppSettings();
  final StudentProfile _emptyProfile = StudentProfile();

  UserData? get _data => ref.read(userDataProvider).valueOrNull;
  List<AcademicTerm> get _terms => _data?.terms ?? _emptyTerms;
  List<Reminder> get _reminders => _data?.reminders ?? _emptyReminders;
  List<StudyGroup> get _groups => _data?.groups ?? _emptyGroups;
  AppSettings get _settings => _data?.settings ?? _emptySettings;
  StudentProfile get _profile => _data?.profile ?? _emptyProfile;

  // Academics tab: 'records' or 'insights'
  String _academicsView = 'records';

  // Bumped whenever the saved data is replaced (load / import) so views that
  // keep their own input state (the calculator) restart from the saved values.
  int _dataEpoch = 0;

  // Save status shown on the Academics tab.
  _SaveState _saveState = _SaveState.saved;
  int _savesInFlight = 0;

  UserDataRepository get _repository => ref.read(userDataRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ------------------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------------------

  Future<void> _loadData() async {
    try {
      await ref.read(userDataProvider.notifier).load(
        widget.user.id,
        defaultTheme: widget.controller.themeMode,
      );
      if (!mounted) return;
      setState(() {
        _dataEpoch++;
        _loaded = true;
        _loading = false;
        _loadError = null;
      });
      await widget.controller.setThemeMode(_settings.themeMode);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e is StorageException
            ? e.message
            : 'Something went wrong while loading your data.';
      });
    }
  }

  UserData _userData() {
    final data = _data;
    if (data == null) throw StateError('User data has not finished loading.');
    return data;
  }

  Future<void> _persist() async {
    // Never save before a successful load, so stored data can't be overwritten.
    if (!_loaded) return;
    _savesInFlight++;
    if (mounted) setState(() => _saveState = _SaveState.saving);
    var failed = false;
    try {
      ref.read(userDataProvider.notifier).publish(widget.user.id, _userData());
      await ref.read(userDataProvider.notifier).persist(widget.user.id, _userData());
    } catch (_) {
      failed = true;
    }
    _savesInFlight--;
    if (!mounted) return;
    if (failed) {
      setState(() => _saveState = _SaveState.failed);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Could not save your changes. They may be lost if you close the app.',
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Retry', onPressed: _persist),
          ),
        );
    } else if (_savesInFlight == 0) {
      setState(() => _saveState = _SaveState.saved);
    }
  }

  /// Applies a change in memory, then saves it.
  void _mutate(VoidCallback change) {
    if (!_loaded || _data == null) return;
    setState(change);
    // Publish immediately so provider-dependent views rebuild before the disk
    // write completes. _persist handles save status and retry on failure.
    ref.read(userDataProvider.notifier).publish(widget.user.id, _userData());
    _persist();
  }

  // ------------------------------------------------------------------------
  // Derived values
  // ------------------------------------------------------------------------

  /// Results and insights, always calculated from the saved records.
  AcademicAnalytics get _stats => AcademicAnalytics.compute(_terms, _settings);

  bool get _hasDemoData =>
      _terms.any((t) => t.isDemo) ||
      _reminders.any((r) => r.isDemo) ||
      _groups.any((g) => g.isDemo);

  String get _scalePrefix => GradeScales.prefix(_settings.gpaScale);

  /// A grade value that is already on the active scale.
  String _formatGrade(double grade) =>
      GradeScales.formatGrade(grade, _settings.gpaScale);

  // ------------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Subscribe to the shared state at the shell boundary.
    ref.watch(userDataProvider);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) return _buildLoadError();

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: _buildNavigationDrawer(),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.onPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.analytics_rounded, color: cs.onPrimary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              'GRADE PULSE',
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _settings.gpaScale,
                    dropdownColor: cs.surfaceContainerHigh,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.onPrimary.withValues(alpha: 0.8),
                      size: 18,
                    ),
                    selectedItemBuilder: (ctx) => AppSettings.gpaScales
                        .map(
                          (s) => Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              s,
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    items: AppSettings.gpaScales
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _mutate(() => _settings.gpaScale = val);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings and preferences',
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: _showAntigravityTab
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: AntigravityJsonView(
                  key: ValueKey('antigravity-$_dataEpoch'),
                  currentDataJson: UserDataCodec.encode(_userData()),
                  premadeSourcePath: _bundledSamplePath,
                  onApply: _applyAntigravityJson,
                  onClose: () => setState(() => _showAntigravityTab = false),
                ),
              ),
            )
          : Column(
              children: [
                _buildExecutiveSummaryHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: _buildTabContent(),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _showAntigravityTab ? null : Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: cs.surface,
          selectedItemColor: cs.primary,
          unselectedItemColor: cs.onSurfaceVariant,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          onTap: (idx) => setState(() {
            _showAntigravityTab = false;
            _currentIndex = idx;
            if (idx == 2) _remindersOnly = false;
          }),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.school_outlined),
              activeIcon: Icon(Icons.school),
              label: 'Academics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_outlined),
              activeIcon: Icon(Icons.groups),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month),
              label: 'Calendar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calculate_outlined),
              activeIcon: Icon(Icons.calculate),
              label: 'Calculator',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------
  // Navigation drawer, calculator tab, and profile
  // ------------------------------------------------------------------------

  Widget _buildNavigationDrawer() {
    final cs = Theme.of(context).colorScheme;
    final onDestination = (String destination) {
      Navigator.pop(context);
      switch (destination) {
        case 'academics':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 0;
            _academicsView = 'records';
          });
          break;
        case 'groups':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 1;
          });
          break;
        case 'calendar':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 2;
            _remindersOnly = false;
          });
          break;
        case 'reminders':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 2;
            _remindersOnly = true;
            _reminderCategoryFilter = 'All';
            _reminderStatusFilter = 'All';
          });
          break;
        case 'analytics':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 0;
            _academicsView = 'insights';
          });
          break;
        case 'me':
          setState(() {
            _showAntigravityTab = false;
            _currentIndex = 4;
          });
          break;
        case 'antigravity':
          setState(() => _showAntigravityTab = true);
          break;
        case 'calculator':
          _openGradeCalculator();
          break;
        case 'settings':
          _showSettingsSheet();
          break;
        case 'import':
          _importFromFile();
          break;
        case 'export':
          _exportData();
          break;
        case 'logout':
          _logout();
          break;
      }
    };

    Widget destination({
      required String id,
      required String label,
      required IconData icon,
      required String key,
    }) {
      final selected = switch (id) {
        'academics' => _currentIndex == 0 && _academicsView == 'records',
        'analytics' => _currentIndex == 0 && _academicsView == 'insights',
        'groups' => _currentIndex == 1,
        'calendar' => _currentIndex == 2 && !_remindersOnly,
        'reminders' => _currentIndex == 2 && _remindersOnly,
        'me' => _currentIndex == 4 && !_showAntigravityTab,
        'antigravity' => _showAntigravityTab,
        _ => false,
      };
      return ListTile(
        key: ValueKey(key),
        selected: selected,
        selectedColor: cs.primary,
        selectedTileColor: cs.primary.withValues(alpha: 0.09),
        leading: Icon(icon),
        title: Text(label),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () => onDestination(id),
      );
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: BoxDecoration(color: cs.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: cs.onPrimary.withValues(alpha: 0.16),
                    foregroundColor: cs.onPrimary,
                    child: Text(_profileInitials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(widget.user.email, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('GRADE PULSE', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.8), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                children: [
                  destination(id: 'academics', label: 'Academics', icon: Icons.school_outlined, key: 'drawer-academics'),
                  destination(id: 'groups', label: 'Groups', icon: Icons.groups_outlined, key: 'drawer-groups'),
                  destination(id: 'calendar', label: 'Calendar', icon: Icons.calendar_month_outlined, key: 'drawer-calendar'),
                  destination(id: 'calculator', label: 'Grade Calculator', icon: Icons.calculate_outlined, key: 'drawer-calculator'),
                  destination(id: 'analytics', label: 'Academic Analytics', icon: Icons.insights_outlined, key: 'drawer-analytics'),
                  destination(id: 'reminders', label: 'Reminders and Tasks', icon: Icons.task_alt, key: 'drawer-reminders'),
                  destination(id: 'me', label: 'Me / Profile', icon: Icons.person_outline_rounded, key: 'drawer-me'),
                  const Divider(height: 24),
                  destination(id: 'settings', label: 'Settings and Theme', icon: Icons.settings_outlined, key: 'drawer-settings'),
                  destination(id: 'antigravity', label: 'Antigravity', icon: Icons.code_rounded, key: 'drawer-antigravity'),
                  const Divider(height: 24),
                  ListTile(
                    key: const ValueKey('drawer-logout'),
                    leading: Icon(Icons.logout, color: cs.error),
                    title: Text('Log Out', style: TextStyle(color: cs.error)),
                    onTap: () => onDestination('logout'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Your grades and preferences are saved to this account.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  String get _profileInitials => widget.user.initials;

  void _openGradeCalculator() {
    setState(() {
      _showAntigravityTab = false;
      _currentIndex = 3;
    });
  }

  Widget _buildProfileTab() {
    final cs = Theme.of(context).colorScheme;
    final stats = _stats;
    final profileRows = <(String, String)>[
      ('School', _profile.school),
      ('Program / Major', _profile.program),
      ('Year Level', _profile.yearLevel),
      ('Student Information', _profile.studentInfo),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('MY PROFILE'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  child: Text(_profileInitials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                ),
                const SizedBox(height: 12),
                Text(widget.user.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(widget.user.email, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _showEditProfileDialog,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Profile'),
                )),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ACADEMIC OVERVIEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.onSurfaceVariant)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _profileStat('Cumulative ${_scalePrefix.toUpperCase()}', stats.cumulativeGrade == null ? '—' : _formatGrade(stats.cumulativeGrade!))),
                const SizedBox(width: 12),
                Expanded(child: _profileStat('Total Units', '${stats.totalUnits}')),
                const SizedBox(width: 12),
                Expanded(child: _profileStat('Subjects', '${stats.subjectCount}')),
              ]),
              if (stats.cumulativePercent != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: (stats.cumulativePercent! / 100).clamp(0.0, 1.0).toDouble()),
                const SizedBox(height: 4),
                Text('${stats.cumulativePercent!.toStringAsFixed(1)}% recorded academic average', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
        Card(
          child: Column(children: [
            for (final row in profileRows)
              ListTile(
                dense: true,
                leading: Icon(switch (row.$1) { 'School' => Icons.account_balance_outlined, 'Program / Major' => Icons.menu_book_outlined, 'Year Level' => Icons.calendar_today_outlined, _ => Icons.badge_outlined }, color: cs.primary),
                title: Text(row.$1, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                subtitle: Text(row.$2.trim().isEmpty ? 'Not set' : row.$2, style: TextStyle(fontSize: 14, color: cs.onSurface)),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        _sectionTitle('QUICK ACTIONS'),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.calculate_outlined), title: const Text('Grade Calculator'), subtitle: const Text('Calculate your overall weighted grade from seven scores'), onTap: _openGradeCalculator),
            ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Appearance'), subtitle: Text(_themeLabel(widget.controller.themeMode)), onTap: _showSettingsSheet),
            ListTile(leading: const Icon(Icons.code_rounded), title: const Text('Antigravity'), subtitle: const Text('View and edit account data structure'), onTap: () => setState(() => _showAntigravityTab = true)),
            ListTile(leading: Icon(Icons.logout, color: cs.error), title: Text('Log Out', style: TextStyle(color: cs.error)), onTap: _logout),
          ]),
        ),
      ],
    );
  }

  Widget _profileStat(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 20, color: cs.onSurface, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Lilac light mode',
    ThemeMode.dark => 'Midnight Blue dark mode',
    ThemeMode.system => 'Follow system appearance',
  };

  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: widget.user.name);
    final emailCtrl = TextEditingController(text: widget.user.email);
    final schoolCtrl = TextEditingController(text: _profile.school);
    final programCtrl = TextEditingController(text: _profile.program);
    final yearCtrl = TextEditingController(text: _profile.yearLevel);
    final infoCtrl = TextEditingController(text: _profile.studentInfo);
    final formKey = GlobalKey<FormState>();
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit Profile'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full Name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null),
                const SizedBox(height: 8),
                TextFormField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address', helperText: 'Used to sign in to this local account'), validator: (v) => AuthService.isValidEmail((v ?? '').trim()) ? null : 'Enter a valid email'),
                const SizedBox(height: 8),
                TextFormField(controller: schoolCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'School / Campus')),
                const SizedBox(height: 8),
                TextFormField(controller: programCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Program / Major')),
                const SizedBox(height: 8),
                TextFormField(controller: yearCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Year Level')),
                const SizedBox(height: 8),
                TextFormField(controller: infoCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Additional Academic Information (non-sensitive, optional)', helperText: 'Do not enter student ID numbers or private account details.')),
              ]),
            )),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setLocal(() => saving = true);
                final nextProfile = StudentProfile(
                  school: schoolCtrl.text.trim(),
                  program: programCtrl.text.trim(),
                  yearLevel: yearCtrl.text.trim(),
                  studentInfo: infoCtrl.text.trim(),
                );
                _savesInFlight++;
                if (mounted) setState(() => _saveState = _SaveState.saving);
                try {
                  await widget.controller.updateProfile(
                    name: nameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                  );
                  // Persist the non-sensitive academic profile using the same
                  // per-user storage service as grades, reminders and groups.
                  final nextData = UserData(
                    terms: _terms,
                    reminders: _reminders,
                    groups: _groups,
                    settings: _settings,
                    profile: nextProfile,
                  );
                  await ref.read(userDataProvider.notifier).replaceAndPersist(widget.user.id, nextData);
                  if (!mounted) return;
                  setState(() {
                    _savesInFlight--;
                    if (_savesInFlight == 0) _saveState = _SaveState.saved;
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('Profile updated and saved.');
                } catch (e) {
                  if (mounted) {
                    setState(() {
                      _savesInFlight = (_savesInFlight - 1).clamp(0, 1000000).toInt();
                      _saveState = _SaveState.failed;
                    });
                  }
                  if (ctx.mounted) {
                    setLocal(() => saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                }
              },
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Profile'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose(); emailCtrl.dispose(); schoolCtrl.dispose(); programCtrl.dispose(); yearCtrl.dispose(); infoCtrl.dispose();
  }

  Widget _buildLoadError() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 40, color: cs.error),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load your data',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _loadError ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _loadError = null;
                      });
                      _loadData();
                    },
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: _logout,
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveSummaryHeader() {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);

    final stats = _stats;
    final String standingLabel;
    final Color standingColor;
    if (!stats.hasData) {
      standingLabel = stats.subjectCount == 0 ? 'No subjects yet' : 'No grades yet';
      standingColor = cs.onSurfaceVariant;
    } else if (stats.cumulativePercent! >= GradeScales.passingPercent) {
      standingLabel = 'Good Standing';
      standingColor = colors.success;
    } else {
      standingLabel = 'Needs Attention';
      standingColor = colors.warning;
    }

    final headline = stats.cumulativeGrade == null
        ? '—'
        : _formatGrade(stats.cumulativeGrade!);
    final muted = cs.onPrimary.withValues(alpha: 0.85);
    final divider = cs.onPrimary.withValues(alpha: 0.25);

    return Container(
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Divider(color: divider, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: divider, width: 1),
                ),
                child: Center(
                  child: Text(
                    widget.user.initials,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      widget.user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 3, backgroundColor: standingColor),
                    const SizedBox(width: 6),
                    Text(
                      standingLabel,
                      style: TextStyle(
                        color: standingColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CUMULATIVE ${_scalePrefix.toUpperCase()}',
                      style: TextStyle(
                        color: muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                Container(height: 36, width: 1, color: divider),
                Column(
                  children: [
                    Text(
                      'TOTAL UNITS',
                      style: TextStyle(
                        color: muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.totalUnits}',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(height: 36, width: 1, color: divider),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'TERMS',
                      style: TextStyle(
                        color: muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.terms.length}',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorTab() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CalculatorView(
          key: ValueKey('calculator-$_dataEpoch'),
          settings: _settings,
          onChanged: _persist,
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_currentIndex) {
      case 0:
        return AcademicsView(child: _buildAcademicsTab());
      case 1:
        return StudyGroupsView(child: _buildGroupsTab());
      case 2:
        return CalendarView(
          child: _buildCalendarAndRemindersTab(remindersOnly: _remindersOnly),
        );
      case 3:
        return GradeCalculatorView(child: _buildCalculatorTab());
      case 4:
        return ProfileView(child: _buildProfileTab());
      default:
        return const SizedBox();
    }
  }

  // ------------------------------------------------------------------------
  // Shared small widgets
  // ------------------------------------------------------------------------

  Widget _sectionTitle(String text) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: cs.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------
  // ACADEMICS TAB
  // ------------------------------------------------------------------------

  Widget _buildAcademicsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.calculate_outlined),
            ),
            title: const Text('Grade Calculator', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Calculate your overall grade from class activities and tests.'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: _openGradeCalculator,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'records',
                icon: Icon(Icons.list_alt_outlined),
                label: Text('Records'),
              ),
              ButtonSegment(
                value: 'insights',
                icon: Icon(Icons.insights_outlined),
                label: Text('Insights'),
              ),
            ],
            selected: {_academicsView},
            onSelectionChanged: (s) => setState(() => _academicsView = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (_academicsView == 'insights')
          InsightsView(
            stats: _stats,
            settings: _settings,
            onEditTarget: _showTargetDialog,
          )
        else
          ..._buildRecords(),
      ],
    );
  }

  List<Widget> _buildRecords() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _sectionTitle('ACADEMIC TERMS'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () => _showTermDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text(
              'Add Term',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      _buildSaveStatus(),
      const SizedBox(height: 12),
      if (_terms.isEmpty)
        _emptyState(
          icon: Icons.school_outlined,
          message: 'No academic terms yet. Add a term, then add subjects and record your scores.',
        )
      else
        ..._terms.map((term) => _buildTermCard(term)),
    ];
  }

  Widget _buildSaveStatus() {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final style = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    switch (_saveState) {
      case _SaveState.saving:
        return Row(
          children: [
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text('Saving…', style: style),
          ],
        );
      case _SaveState.saved:
        return Row(
          children: [
            Icon(Icons.check_circle_outline, size: 13, color: colors.success),
            const SizedBox(width: 6),
            Text('All changes saved on this device', style: style),
          ],
        );
      case _SaveState.failed:
        return Row(
          children: [
            Icon(Icons.error_outline, size: 13, color: cs.error),
            const SizedBox(width: 6),
            Text('Not saved', style: style.copyWith(color: cs.error)),
            TextButton(
              onPressed: _persist,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 11)),
            ),
          ],
        );
    }
  }

  Widget _buildTermCard(AcademicTerm term) {
    final cs = Theme.of(context).colorScheme;
    final percent = GradeMath.weightedPercent(term.courses);
    final grade = GradeMath.weightedGrade(term.courses, _settings.gpaScale, _settings);
    final units = GradeMath.totalUnits(term.courses);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        term.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      if (term.isDemo)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SAMPLE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Term options',
                  icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
                  onSelected: (v) {
                    if (v == 'rename') _showTermDialog(term: term);
                    if (v == 'delete') _deleteTerm(term);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename term')),
                    PopupMenuItem(value: 'delete', child: Text('Delete term')),
                  ],
                ),
              ],
            ),
            Text(
              percent == null
                  ? '${term.courses.length} subject(s) · $units units · no grades yet'
                  : 'Term $_scalePrefix: ${_formatGrade(grade!)}  ·  ${percent.toStringAsFixed(1)}%  ·  ${term.courses.length} subject(s) · $units units',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (term.courses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No subjects in this term yet.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ...term.courses.map((course) => _buildCourseItem(term, course)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: cs.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _showCourseDialog(term),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text(
                  'Add Subject',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Quiz':
        return Icons.quiz_outlined;
      case 'Assignment':
        return Icons.assignment_outlined;
      case 'Exam':
        return Icons.edit_note;
      case 'Laboratory':
        return Icons.science_outlined;
      case 'Project':
        return Icons.build_circle_outlined;
      default:
        return Icons.check_circle_outline;
    }
  }

  Widget _buildCourseItem(AcademicTerm term, Course course) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final percent = course.percent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  course.code,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${course.units} ${course.units == 1 ? 'Unit' : 'Units'}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    percent == null ? '—' : '${percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: cs.onSurface,
                    ),
                  ),
                  if (percent != null)
                    Text(
                      GradeScales.formatPercentOnActiveScale(percent, _settings),
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              SizedBox(
                width: 32,
                height: 24,
                child: PopupMenuButton<String>(
                  tooltip: 'Subject options',
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
                  onSelected: (v) {
                    if (v == 'edit') _showCourseDialog(term, course: course);
                    if (v == 'delete') _deleteCourse(term, course);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit subject')),
                    PopupMenuItem(value: 'delete', child: Text('Delete subject')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            course.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ASSESSMENTS',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              InkWell(
                onTap: () => _showAssessmentDialog(course),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '+ Assessment',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...course.assessments.map(
            (a) => InkWell(
              onTap: () => _showAssessmentDialog(course, assessment: a),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5.0),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcon(a.category),
                      size: 14,
                      color: a.scoreAchieved > a.maxScore ? cs.error : colors.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${a.title}  ·  ${a.category}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    Text(
                      '${_fmtNum(a.scoreAchieved)} / ${_fmtNum(a.maxScore)}  (${a.percentage.toStringAsFixed(0)}%)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (course.assessments.isEmpty)
            Text(
              'No assessments yet. Add a quiz, exam, lab or project score.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  // ------------------------------------------------------------------------
  // GROUPS TAB
  // ------------------------------------------------------------------------

  Widget _buildGroupsTab() {
    final cs = Theme.of(context).colorScheme;
    final query = _groupSearch.trim().toLowerCase();
    final visibleGroups = _groups.where((g) {
      if (query.isEmpty) return true;
      return g.name.toLowerCase().contains(query) ||
          g.courseCode.toLowerCase().contains(query) ||
          g.members.any((m) => m.toLowerCase().contains(query)) ||
          g.description.toLowerCase().contains(query) ||
          g.notes.toLowerCase().contains(query);
    }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('STUDY GROUPS & TEAMS'),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () => _showGroupDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Group', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) => setState(() => _groupSearch = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search groups, subjects, or members',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (_groups.isEmpty)
          _emptyState(
            icon: Icons.groups_outlined,
            message: 'No study groups yet. Add a group to keep track of your teammates, tasks, and sessions.',
          )
        else if (visibleGroups.isEmpty)
          _emptyState(icon: Icons.search_off, message: 'No groups match your search.')
        else
          ...visibleGroups.map((g) {
            final groupReminders = _reminders.where((r) => r.groupId == g.id).toList()
              ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
            final completeCount = groupReminders.where((r) => r.isCompleted).length;
            final upcomingSession = groupReminders.where((r) =>
              r.category == 'Group Study' && !r.isCompleted && !r.dateTime.isBefore(DateTime.now())
            ).firstOrNull;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.groups_rounded, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
                            if (g.courseCode.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(g.courseCode, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
                            ],
                            if (g.description.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(g.description, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            ],
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      g.members.isEmpty ? 'No members listed' : 'Members (${g.members.length}): ${g.members.join(', ')}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                    if (g.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Notes: ${g.notes}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.checklist_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        'Tasks and sessions: $completeCount/${groupReminders.length} completed',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      )),
                    ]),
                    if (upcomingSession != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.event, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          'Next session: ${upcomingSession.title} • ${_formatDateTime(upcomingSession.dateTime)}',
                          style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600),
                        )),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _showGroupDialog(group: g),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Manage'),
                        ),
                        TextButton.icon(
                          onPressed: () => _showGroupTasksDialog(g),
                          icon: const Icon(Icons.checklist, size: 16),
                          label: const Text('Tasks'),
                        ),
                        TextButton.icon(
                          onPressed: () => _showReminderDialog(group: g, defaultCategory: 'Group Study'),
                          icon: const Icon(Icons.event_available_outlined, size: 16),
                          label: const Text('Schedule Session'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  List<Reminder> get _calendarReminders => _reminders.where((r) =>
    _reminderCategoryFilter == 'All' || r.category == _reminderCategoryFilter
  ).toList();

  List<Reminder> get _filteredReminderTasks {
    final now = DateTime.now();
    final values = _calendarReminders.where((r) {
      switch (_reminderStatusFilter) {
        case 'Pending':
          return !r.isCompleted;
        case 'Completed':
          return r.isCompleted;
        case 'Upcoming':
          return !r.isCompleted && !r.dateTime.isBefore(now);
        case 'Overdue':
          return !r.isCompleted && r.dateTime.isBefore(now);
        default:
          return true;
      }
    }).toList();
    values.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return values;
  }

  Widget _buildCalendarAndRemindersTab({bool remindersOnly = false}) {
    final cs = Theme.of(context).colorScheme;
    final sorted = _filteredReminderTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (remindersOnly) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _sectionTitle('REMINDERS & TASKS')),
              FilledButton.icon(
                onPressed: () => _showReminderDialog(),
                icon: const Icon(Icons.add_task, size: 16),
                label: const Text('Add Task'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (!remindersOnly) ...[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: ['Day', 'Week', 'Month', 'Year'].map((view) {
                final isSelected = _calendarView == view;
                return GestureDetector(
                  onTap: () => setState(() => _calendarView = view),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: isSelected ? Border.all(color: cs.outlineVariant) : null,
                    ),
                    child: Text(view, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? cs.primary : cs.onSurfaceVariant)),
                  ),
                );
              }).toList()),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              onPressed: () => _showReminderDialog(),
              icon: const Icon(Icons.add_alarm, size: 16),
              label: const Text('Add Reminder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: _reminderCategoryFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Event category', isDense: true),
            items: ['All', ...Reminder.categories].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _reminderCategoryFilter = v ?? 'All'),
          )),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            value: _reminderStatusFilter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Task status', isDense: true),
            items: const ['All', 'Pending', 'Upcoming', 'Overdue', 'Completed'].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _reminderStatusFilter = v ?? 'All'),
          )),
        ]),
        if (!remindersOnly) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _buildCalendarHeader(),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _buildCalendarViewContent(),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _buildSelectedDateEvents(),
          const SizedBox(height: 18),
        ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _sectionTitle('SCHEDULED REMINDERS & TASKS'),
          Text('${_reminders.where((r) => !r.isCompleted).length} Pending', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          _emptyState(icon: Icons.event_available_outlined, message: 'No reminders match these filters. Add an assignment, exam, project, or study session to get started.')
        else
          ...sorted.map((reminder) => _buildReminderTile(reminder)),
      ],
    );
  }

  Widget _buildSelectedDateEvents() {
    final cs = Theme.of(context).colorScheme;
    final entries = _calendarReminders.where((r) => DateUtils.isSameDay(r.dateTime, _selectedDate)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event_note, color: cs.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Events on ${_monthName(_selectedDate.month)} ${_selectedDate.day}, ${_selectedDate.year}', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface))),
            Text('${entries.length}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text('No events on this date. Select another date or add a reminder.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
          else
            ...entries.map((r) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.category == 'Exam' ? Icons.assignment_late_outlined : r.category == 'Group Study' ? Icons.groups_outlined : Icons.event_outlined, color: cs.primary),
              title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${r.category} • ${_timeLabel(r.dateTime)}${r.courseCode.isNotEmpty ? ' • ${r.courseCode}' : ''}${r.description.trim().isNotEmpty ? '\n${r.description.trim()}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: 'Edit event', icon: const Icon(Icons.edit_outlined), onPressed: () => _showReminderDialog(reminder: r)),
            )),
        ]),
      ),
    );
  }

  DateTime _startOfWeek(DateTime d) {
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(Duration(days: base.weekday % 7)); // Sunday start
  }

  Widget _buildCalendarHeader() {
    final cs = Theme.of(context).colorScheme;
    String headerText = '';
    if (_calendarView == 'Day') {
      headerText = '${_focusedDate.day} ${_monthName(_focusedDate.month)} ${_focusedDate.year}';
    } else if (_calendarView == 'Week') {
      final start = _startOfWeek(_focusedDate);
      final end = start.add(const Duration(days: 6));
      headerText = '${start.day} ${_monthName(start.month)} - ${end.day} ${_monthName(end.month)} ${end.year}';
    } else if (_calendarView == 'Month') {
      headerText = '${_monthName(_focusedDate.month)} ${_focusedDate.year}';
    } else {
      headerText = '${_focusedDate.year} Academic Calendar';
    }

    void shift(int amount) {
      setState(() {
        if (_calendarView == 'Day') {
          _focusedDate = _focusedDate.add(Duration(days: amount));
        } else if (_calendarView == 'Week') {
          _focusedDate = _focusedDate.add(Duration(days: 7 * amount));
        } else if (_calendarView == 'Month') {
          _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + amount, 1);
        } else {
          _focusedDate = DateTime(_focusedDate.year + amount, 1, 1);
        }
        _selectedDate = _focusedDate;
      });
    }

    return Row(
      children: [
        Expanded(child: Text(headerText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface))),
        TextButton.icon(
          onPressed: () => setState(() {
            _focusedDate = DateTime.now();
            _selectedDate = DateTime.now();
          }),
          icon: const Icon(Icons.today, size: 16),
          label: const Text('Today'),
        ),
        IconButton(tooltip: 'Previous', icon: const Icon(Icons.chevron_left, size: 22), onPressed: () => shift(-1)),
        IconButton(tooltip: 'Next', icon: const Icon(Icons.chevron_right, size: 22), onPressed: () => shift(1)),
      ],
    );
  }

  Widget _buildCalendarViewContent() {
    switch (_calendarView) {
      case 'Day':
        return _buildDayView();
      case 'Week':
        return _buildWeekView();
      case 'Month':
        return _buildMonthGrid();
      case 'Year':
        return _buildYearView();
      default:
        return _buildMonthGrid();
    }
  }

  Widget _buildMonthGrid() {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedDate.year,
      _focusedDate.month,
    );
    final firstDayOffset =
        DateTime(_focusedDate.year, _focusedDate.month, 1).weekday % 7;
    final totalCells = daysInMonth + firstDayOffset;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (context, index) {
            if (index < firstDayOffset) return const SizedBox();
            final dayNumber = index - firstDayOffset + 1;
            final cellDate = DateTime(
              _focusedDate.year,
              _focusedDate.month,
              dayNumber,
            );
            final isToday = DateUtils.isSameDay(cellDate, DateTime.now());
            final isSelected = DateUtils.isSameDay(cellDate, _selectedDate);
            final hasReminders = _calendarReminders.any(
              (r) => DateUtils.isSameDay(r.dateTime, cellDate),
            );

            return GestureDetector(
              onTap: () => setState(() { _selectedDate = cellDate; _focusedDate = cellDate; }),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary
                      : (isToday
                            ? cs.primary.withValues(alpha: 0.12)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                  border: isToday ? Border.all(color: cs.primary, width: 1) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isToday || isSelected)
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? cs.onPrimary
                            : (isToday ? cs.primary : cs.onSurface),
                      ),
                    ),
                    if (hasReminders)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isSelected ? cs.onPrimary : colors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDayView() {
    final cs = Theme.of(context).colorScheme;
    final dayReminders = _calendarReminders
        .where((r) => DateUtils.isSameDay(r.dateTime, _focusedDate))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Schedule for ${_monthName(_focusedDate.month)} ${_focusedDate.day}, ${_focusedDate.year}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (dayReminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No academic events or reminders for this day.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
          )
        else
          ...dayReminders.map((r) => _buildReminderTile(r)),
      ],
    );
  }

  Widget _buildWeekView() {
    final cs = Theme.of(context).colorScheme;
    final startOfWeek = _startOfWeek(_focusedDate);

    return Column(children: List.generate(7, (index) {
      final day = startOfWeek.add(Duration(days: index));
      final dayReminders = _calendarReminders.where((r) => DateUtils.isSameDay(r.dateTime, day)).toList();
      final isToday = DateUtils.isSameDay(day, DateTime.now());
      final isSelected = DateUtils.isSameDay(day, _selectedDate);
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() { _selectedDate = day; _focusedDate = day; }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected ? cs.primaryContainer : isToday ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? cs.primary : isToday ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant),
          ),
          child: Row(children: [
            SizedBox(
              width: 66,
              child: Text('${_weekdayName(day.weekday)} ${day.day}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? cs.onPrimaryContainer : isToday ? cs.primary : cs.onSurface)),
            ),
            const VerticalDivider(width: 12),
            Expanded(
              child: dayReminders.isEmpty
                  ? Text('No events', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))
                  : Wrap(spacing: 6, runSpacing: 4, children: dayReminders.map((r) => Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(r.isCompleted ? Icons.check_circle : Icons.event, size: 13, color: cs.primary),
                      label: Text(r.title, style: TextStyle(fontSize: 10, color: cs.onSurface)),
                    )).toList()),
            ),
          ]),
        ),
      );
    }));
  }

  Widget _buildYearView() {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.6,
      ),
      itemBuilder: (context, index) {
        final monthDate = DateTime(_focusedDate.year, index + 1, 1);
        final isCurrentMonth =
            monthDate.month == DateTime.now().month &&
            monthDate.year == DateTime.now().year;
        final eventCount = _calendarReminders.where((r) =>
          r.dateTime.year == monthDate.year && r.dateTime.month == monthDate.month
        ).length;

        return GestureDetector(
          onTap: () {
            setState(() {
              _focusedDate = monthDate;
              _selectedDate = monthDate;
              _calendarView = 'Month';
            });
          },
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isCurrentMonth ? cs.primary : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _monthName(index + 1).substring(0, 3),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isCurrentMonth ? cs.onPrimary : cs.onSurface),
                  ),
                  if (eventCount > 0) ...[
                    const SizedBox(height: 3),
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: isCurrentMonth ? cs.onPrimary : cs.primary, shape: BoxShape.circle)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReminderTile(Reminder reminder) {
    final cs = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final dueDay = DateTime(reminder.dateTime.year, reminder.dateTime.month, reminder.dateTime.day);
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = !reminder.isCompleted && reminder.dateTime.isBefore(now);
    final isDueSoon = !reminder.isCompleted && !isOverdue && dueDay.difference(today).inDays <= 2;

    Color tagColor = cs.primary;
    if (reminder.category == 'Exam') tagColor = cs.error;
    if (reminder.category == 'Group Study') tagColor = colors.info;
    if (reminder.category == 'Project') tagColor = cs.tertiary;
    final priorityColor = reminder.priority == 'High'
        ? cs.error
        : reminder.priority == 'Low'
            ? cs.onSurfaceVariant
            : cs.tertiary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _showReminderDialog(reminder: reminder),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Checkbox(
          value: reminder.isCompleted,
          onChanged: (val) => _mutate(() => reminder.isCompleted = val ?? false),
        ),
        title: Text(
          reminder.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            decoration: reminder.isCompleted ? TextDecoration.lineThrough : null,
            color: reminder.isCompleted ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              _smallTag(reminder.category, tagColor),
              _smallTag('${reminder.priority} priority', priorityColor),
              if (isOverdue) _smallTag('Overdue', cs.error),
              if (isDueSoon) _smallTag('Due soon', cs.tertiary),
              if (reminder.groupId != null) _smallTag('Group task', cs.primary),
            ]),
            const SizedBox(height: 4),
            Text(
              '${reminder.courseCode.isEmpty ? 'General' : reminder.courseCode} • ${_formatDateTime(reminder.dateTime)}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            if (reminder.description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(reminder.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
        trailing: IconButton(
          tooltip: 'Delete reminder',
          icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant),
          onPressed: () => _deleteReminder(reminder),
        ),
      ),
    );
  }

  Widget _smallTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  String _formatDateTime(DateTime dateTime) =>
      '${_monthName(dateTime.month)} ${dateTime.day}, ${dateTime.year} • ${_timeLabel(dateTime)}';

  String _timeLabel(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${dateTime.hour >= 12 ? 'PM' : 'AM'}';
  }

  // Helper Functions
  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _weekdayName(int weekday) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[weekday % 7];
  }

  // ------------------------------------------------------------------------
  // Dialogs (create / edit / delete, all saved)
  // ------------------------------------------------------------------------

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  Future<void> _showTermDialog({AcademicTerm? term}) async {
    final controller = TextEditingController(text: term?.name ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(term == null ? 'Add Academic Term' : 'Rename Term'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g., 2nd Year - 1st Term'),
            validator: (v) {
              final missing = _required(v, 'Enter a term name');
              if (missing != null) return missing;
              final name = v!.trim().toLowerCase();
              final duplicate = _terms.any(
                (t) => !identical(t, term) && t.name.trim().toLowerCase() == name,
              );
              return duplicate ? 'A term with this name already exists' : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final name = controller.text.trim();
              _mutate(() {
                if (term == null) {
                  _terms.add(AcademicTerm(name: name, courses: <Course>[]));
                } else {
                  term.name = name;
                }
              });
              Navigator.pop(ctx);
            },
            child: Text(term == null ? 'Save' : 'Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTerm(AcademicTerm term) async {
    final ok = await _confirm(
      title: 'Delete term?',
      message:
          '"${term.name}" and all of its subjects and assessments will be removed.',
      confirmLabel: 'Delete',
    );
    if (ok) _removeWithUndo(_terms, term, 'Term "${term.name}" deleted');
  }

  Future<void> _showCourseDialog(AcademicTerm term, {Course? course}) async {
    final codeCtrl = TextEditingController(text: course?.code ?? '');
    final titleCtrl = TextEditingController(text: course?.title ?? '');
    final unitsCtrl = TextEditingController(text: '${course?.units ?? 3}');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(course == null ? 'Add Subject' : 'Edit Subject'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Subject Code'),
                  validator: (v) {
                    final missing = _required(v, 'Enter a subject code');
                    if (missing != null) return missing;
                    final code = v!.trim().toLowerCase();
                    final duplicate = term.courses.any(
                      (c) => !identical(c, course) && c.code.trim().toLowerCase() == code,
                    );
                    return duplicate ? 'This term already has a subject with that code' : null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Subject Title'),
                  validator: (v) => _required(v, 'Enter a subject title'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: unitsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Units / Credits'),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 1 || n > 30) return 'Enter a whole number from 1 to 30';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final code = codeCtrl.text.trim();
              final title = titleCtrl.text.trim();
              final units = int.parse(unitsCtrl.text.trim());
              _mutate(() {
                if (course == null) {
                  term.courses.add(
                    Course(
                      code: code,
                      title: title,
                      units: units,
                      assessments: <Assessment>[],
                    ),
                  );
                } else {
                  course.code = code;
                  course.title = title;
                  course.units = units;
                }
              });
              Navigator.pop(ctx);
            },
            child: Text(course == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCourse(AcademicTerm term, Course course) async {
    final ok = await _confirm(
      title: 'Delete subject?',
      message: '"${course.code}" and its assessments will be removed.',
      confirmLabel: 'Delete',
    );
    if (ok) _removeWithUndo(term.courses, course, 'Subject "${course.code}" deleted');
  }

  Future<void> _showAssessmentDialog(
    Course course, {
    Assessment? assessment,
  }) async {
    final titleCtrl = TextEditingController(text: assessment?.title ?? '');
    final scoreCtrl = TextEditingController(
      text: assessment == null ? '' : _fmtNum(assessment.scoreAchieved),
    );
    final maxCtrl = TextEditingController(
      text: assessment == null ? '100' : _fmtNum(assessment.maxScore),
    );
    final formKey = GlobalKey<FormState>();
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    var category = assessment?.category ?? 'Quiz';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
        title: Text(assessment == null ? 'Add Assessment' : 'Edit Assessment'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Assessment Title'),
                  validator: (v) => _required(v, 'Enter a title'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: Assessment.categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setLocal(() => category = v ?? category),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: scoreCtrl,
                  keyboardType: keyboard,
                  decoration: const InputDecoration(labelText: 'Score Achieved'),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || !n.isFinite) return 'Enter a number';
                    if (n < 0) return 'Scores cannot be negative';
                    final max = double.tryParse(maxCtrl.text.trim());
                    if (max != null && max.isFinite && max > 0 && n > max) {
                      return 'Cannot be higher than the max score (${_fmtNum(max)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: maxCtrl,
                  keyboardType: keyboard,
                  decoration: const InputDecoration(labelText: 'Max Score'),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').trim());
                    if (n == null || !n.isFinite || n <= 0) return 'Enter a max score above 0';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (assessment != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () async {
                final ok = await _confirm(
                  title: 'Delete assessment?',
                  message: '"${assessment.title}" will be removed.',
                  confirmLabel: 'Delete',
                );
                if (!ok) return;
                _removeWithUndo(
                  course.assessments,
                  assessment,
                  'Assessment "${assessment.title}" deleted',
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final title = titleCtrl.text.trim();
              final score = double.parse(scoreCtrl.text.trim());
              final max = double.parse(maxCtrl.text.trim());
              _mutate(() {
                if (assessment == null) {
                  course.assessments.add(
                    Assessment(
                      title: title,
                      category: category,
                      scoreAchieved: score,
                      maxScore: max,
                    ),
                  );
                } else {
                  assessment.title = title;
                  assessment.category = category;
                  assessment.scoreAchieved = score;
                  assessment.maxScore = max;
                }
              });
              Navigator.pop(ctx);
            },
            child: Text(assessment == null ? 'Save' : 'Update'),
          ),
        ],
      ),
      ),
    );
  }

  /// Removes [item] from [list], saves, and offers Undo.
  void _removeWithUndo<T>(List<T> list, T item, String message) {
    final index = list.indexOf(item);
    if (index < 0) return;
    final epoch = _dataEpoch;
    _mutate(() => list.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // Skip if the data was replaced (e.g. by an import) meanwhile.
              if (!mounted || epoch != _dataEpoch) return;
              _mutate(() => list.insert(index > list.length ? list.length : index, item));
            },
          ),
        ),
      );
  }

  Future<void> _showTargetDialog() async {
    final ctrl = TextEditingController(
      text: _settings.targetPercent == null ? '' : _fmtNum(_settings.targetPercent!),
    );
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Target average'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Target average (%)',
              helperText: 'The overall average you are aiming for, 1 to 100',
            ),
            validator: (v) {
              final n = double.tryParse((v ?? '').trim());
              if (n == null || !n.isFinite) return 'Enter a number';
              if (n < 1 || n > 100) return 'Enter a value from 1 to 100';
              return null;
            },
          ),
        ),
        actions: [
          if (_settings.targetPercent != null)
            TextButton(
              onPressed: () {
                _mutate(() => _settings.targetPercent = null);
                Navigator.pop(ctx);
              },
              child: const Text('Clear target'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final v = double.parse(ctrl.text.trim());
              _mutate(() => _settings.targetPercent = v);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGradeTables() async {
    final result = await showGradeTableDialog(context, settings: _settings);
    if (result == null || !mounted) return;
    _mutate(() => _settings.gradeBands = result);
  }

  Future<void> _showReminderDialog({
    Reminder? reminder,
    StudyGroup? group,
    String? defaultCategory,
  }) async {
    final titleCtrl = TextEditingController(text: reminder?.title ?? '');
    final courseCtrl = TextEditingController(text: reminder?.courseCode ?? group?.courseCode ?? '');
    final descriptionCtrl = TextEditingController(text: reminder?.description ?? '');
    final formKey = GlobalKey<FormState>();
    String category = reminder?.category ?? defaultCategory ?? 'Assignment';
    String priority = reminder?.priority ?? 'Medium';
    DateTime date = reminder?.dateTime ?? _selectedDate;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(reminder == null ? (group == null ? 'Add Academic Reminder' : category == 'Group Study' ? 'Add Study Session' : 'Add Group Task') : 'Edit Reminder'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) => _required(v, 'Enter a title'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: courseCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Subject / course code (optional)'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: Reminder.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setLocal(() => category = val ?? category),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: Reminder.priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (val) => setLocal(() => priority = val ?? priority),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descriptionCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text('${_monthName(date.month)} ${date.day}, ${date.year}'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setLocal(() => date = DateTime(picked.year, picked.month, picked.day, date.hour, date.minute));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('Time: ${_timeLabel(date)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(date));
                        if (picked != null) {
                          setLocal(() => date = DateTime(date.year, date.month, date.day, picked.hour, picked.minute));
                        }
                      },
                    ),
                  ),
                  if (group != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Linked to: ${group.name}', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final title = titleCtrl.text.trim();
                final code = courseCtrl.text.trim();
                final description = descriptionCtrl.text.trim();
                _mutate(() {
                  if (reminder == null) {
                    _reminders.add(Reminder(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      title: title,
                      courseCode: code,
                      category: category,
                      dateTime: date,
                      description: description,
                      priority: priority,
                      groupId: group?.id,
                    ));
                    _selectedDate = DateTime(date.year, date.month, date.day);
                    _focusedDate = DateTime(date.year, date.month, date.day);
                  } else {
                    reminder.title = title;
                    reminder.courseCode = code;
                    reminder.category = category;
                    reminder.dateTime = date;
                    reminder.description = description;
                    reminder.priority = priority;
                    if (group != null) reminder.groupId = group.id;
                    _selectedDate = DateTime(date.year, date.month, date.day);
                    _focusedDate = DateTime(date.year, date.month, date.day);
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(reminder == null ? 'Save' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteReminder(Reminder reminder) {
    final index = _reminders.indexOf(reminder);
    if (index < 0) return;
    _mutate(() => _reminders.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Reminder deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _mutate(() {
              final at = index > _reminders.length ? _reminders.length : index;
              _reminders.insert(at, reminder);
            }),
          ),
        ),
      );
  }

  Future<void> _showGroupDialog({StudyGroup? group}) async {
    final nameCtrl = TextEditingController(text: group?.name ?? '');
    final courseCtrl = TextEditingController(text: group?.courseCode ?? '');
    final descriptionCtrl = TextEditingController(text: group?.description ?? '');
    final membersCtrl = TextEditingController(text: group?.members.join(', ') ?? '');
    final notesCtrl = TextEditingController(text: group?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group == null ? 'Add Study Group' : 'Manage Group'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Group Name'), validator: (v) => _required(v, 'Enter a group name')),
              const SizedBox(height: 8),
              TextFormField(controller: courseCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Subject / Course Code (optional)')),
              const SizedBox(height: 8),
              TextFormField(controller: descriptionCtrl, maxLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Description (optional)')),
              const SizedBox(height: 8),
              TextFormField(controller: membersCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Members', helperText: 'Separate names with commas')),
              const SizedBox(height: 8),
              TextFormField(controller: notesCtrl, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Discussion notes (optional)')),
              if (group != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: Text('${_reminders.where((r) => r.groupId == group.id).length} linked tasks and sessions', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
              ],
            ]),
          ),
        ),
        actions: [
          if (group != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () async {
                final ok = await _confirm(title: 'Delete group?', message: '"${group.name}" will be removed. Its linked reminders and calendar sessions will remain as ordinary reminders.', confirmLabel: 'Delete');
                if (!ok) return;
                _mutate(() {
                  _groups.remove(group);
                  for (final reminder in _reminders.where((r) => r.groupId == group.id)) {
                    reminder.groupId = null;
                  }
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final name = nameCtrl.text.trim();
              final courseCode = courseCtrl.text.trim();
              final description = descriptionCtrl.text.trim();
              final members = membersCtrl.text.split(',').map((m) => m.trim()).where((m) => m.isNotEmpty).toSet().toList();
              final notes = notesCtrl.text.trim();
              _mutate(() {
                if (group == null) {
                  _groups.add(StudyGroup(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    members: members,
                    notes: notes,
                    courseCode: courseCode,
                    description: description,
                    createdAt: DateTime.now(),
                  ));
                } else {
                  group.name = name;
                  group.courseCode = courseCode;
                  group.description = description;
                  group.members = members;
                  group.notes = notes;
                  // Keep linked group tasks' course code current when useful.
                  for (final reminder in _reminders.where((r) => r.groupId == group.id)) {
                    reminder.courseCode = courseCode;
                  }
                }
              });
              Navigator.pop(ctx);
            },
            child: Text(group == null ? 'Add Group' : 'Save Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupTasksDialog(StudyGroup group) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final tasks = _reminders.where((r) => r.groupId == group.id).toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
          final completed = tasks.where((r) => r.isCompleted).length;
          return AlertDialog(
            title: Text('${group.name} • Tasks'),
            content: SizedBox(
              width: MediaQuery.sizeOf(ctx).width > 520 ? 460 : MediaQuery.sizeOf(ctx).width * 0.85,
              child: tasks.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No linked tasks or sessions yet. Add a task or schedule a study session.'))
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: tasks.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Checkbox(value: task.isCompleted, onChanged: (v) {
                              _mutate(() => task.isCompleted = v ?? false);
                              setLocal(() {});
                            }),
                            title: Text(task.title, style: TextStyle(decoration: task.isCompleted ? TextDecoration.lineThrough : null)),
                            subtitle: Text('${task.category} • ${_formatDateTime(task.dateTime)}\n${task.priority} priority', maxLines: 2, overflow: TextOverflow.ellipsis),
                            isThreeLine: true,
                            trailing: Wrap(children: [
                              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () async {
                                await _showReminderDialog(reminder: task, group: group);
                                if (ctx.mounted) setLocal(() {});
                              }),
                              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () {
                                _deleteReminder(task);
                                setLocal(() {});
                              }),
                            ]),
                          );
                        },
                      ),
                    ),
            ),
            actions: [
              TextButton.icon(onPressed: () async {
                await _showReminderDialog(group: group, defaultCategory: 'Assignment');
                if (ctx.mounted) setLocal(() {});
              }, icon: const Icon(Icons.add_task), label: const Text('Add Task')),
              TextButton.icon(onPressed: () async {
                await _showReminderDialog(group: group, defaultCategory: 'Group Study');
                if (ctx.mounted) setLocal(() {});
              }, icon: const Icon(Icons.event_available), label: const Text('Schedule Session')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Done ($completed/${tasks.length})')),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------------
  // Settings, theme, data management, log out
  // ------------------------------------------------------------------------

  void _changeTheme(ThemeMode mode) {
    _settings.themeMode = mode;
    widget.controller.setThemeMode(mode);
    _persist();
  }

  void _showSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => ListenableBuilder(
        listenable: widget.controller,
        builder: (ctx, _) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          widget.user.initials,
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              widget.user.email,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('APPEARANCE'),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {widget.controller.themeMode},
                      onSelectionChanged: (s) => _changeTheme(s.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Light mode uses Lilac, dark mode uses Midnight Blue.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle('GRADING'),
                  const SizedBox(height: 4),
                  Text(
                    GradeScales.describeActive(_settings),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.table_chart_outlined, color: cs.primary),
                    title: Text('Grade conversion tables', style: TextStyle(color: cs.onSurface)),
                    subtitle: Text(
                      'View or edit how percentages convert to 4.0 GPA and TUP / PLM grades.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _editGradeTables();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined, color: cs.primary),
                    title: Text('Target average', style: TextStyle(color: cs.onSurface)),
                    subtitle: Text(
                      _settings.targetPercent == null
                          ? 'Not set. Used for progress in Insights.'
                          : '${_fmtNum(_settings.targetPercent!)}% (${GradeScales.formatPercentOnActiveScale(_settings.targetPercent!, _settings)})',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showTargetDialog();
                    },
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('DATA'),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.dataset_outlined, color: cs.primary),
                    title: Text('Premade', style: TextStyle(color: cs.onSurface)),
                    subtitle: Text(
                      'Load the pre-configured Grade Pulse dataset. You can customize its records and keep the changes saved to this account.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _loadPremadeData();
                    },
                  ),
                  const SizedBox(height: 8),
                  _sectionTitle('ACCOUNT'),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout, color: cs.error),
                    title: Text('Log out', style: TextStyle(color: cs.error)),
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _logout();
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Local demo mode: your account and data are saved on this '
                    'device only, separately for each account.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const String _bundledSamplePath = 'assets/data/grade_pulse_data.json';

  void _snack(String message, {int seconds = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: Duration(seconds: seconds)),
      );
  }

  Future<void> _importFromFile() async {
    if (!_loaded) return;
    try {
      final picked = await widget.files.pickJsonFile();
      if (picked == null || !mounted) return; // cancelled
      await _reviewAndImport(picked.name, picked.text);
    } catch (e) {
      if (!mounted) return;
      await showDataErrorDialog(context, title: 'Import failed', error: e);
    }
  }

  Future<void> _loadPremadeData() async {
    if (!_loaded) return;
    try {
      final raw = await rootBundle.loadString(_bundledSamplePath);
      if (!mounted) return;
      await _reviewAndImport('Premade defaults', raw);
    } catch (e) {
      if (!mounted) return;
      await showDataErrorDialog(context, title: 'Import failed', error: e);
    }
  }

  Future<void> _applyAntigravityJson(
    String raw,
    ImportMode preferredMode,
  ) async {
    if (!_loaded) return;
    try {
      UserDataCodec.parse(raw);
      await _reviewAndImport(
        'Antigravity editor',
        raw,
        initialMode: preferredMode,
      );
    } catch (e) {
      if (!mounted) return;
      await showDataErrorDialog(context, title: 'Data validation failed', error: e);
    }
  }

  /// Validates [raw], shows the preview, and only after the user confirms
  /// saves the result for the signed-in account. Any failure leaves the
  /// existing records exactly as they were.
  Future<void> _reviewAndImport(
    String sourceLabel,
    String raw, {
    ImportMode initialMode = ImportMode.merge,
  }) async {
    final parsed = UserDataCodec.parse(raw); // throws JsonDataException
    // Make sure everything already saved is on disk, then compare against it.
    await _repository.flush();
    if (!mounted) return;
    final choice = await showImportPreviewDialog(
      context,
      sourceLabel: sourceLabel,
      parsed: parsed,
      current: _userData(),
      initialMode: initialMode,
    );
    if (choice == null || !mounted) return; // cancelled

    final next = choice.outcome.data; // merge keeps the current settings
    final uid = widget.user.id;
    try {
      // Save first: if this fails, nothing on screen has changed either.
      await ref.read(userDataProvider.notifier).replaceAndPersist(uid, next);
    } catch (_) {
      if (!mounted) return;
      await showDataErrorDialog(
        context,
        title: 'Import failed',
        error: const JsonDataException('Your data could not be saved.'),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _dataEpoch++;
    });
    if (choice.mode == ImportMode.replace) {
      await widget.controller.setThemeMode(_settings.themeMode);
    }
    final o = choice.outcome;
    _snack(
      choice.mode == ImportMode.replace
          ? 'Import complete: replaced your data with ${describeCounts(o.added)}.'
          : 'Merge complete: added ${describeCounts(o.added)}'
              '${o.skippedDuplicates > 0 ? ', skipped ${o.skippedDuplicates} duplicate(s)' : ''}.',
      seconds: 6,
    );
  }

  Future<void> _exportData() async {
    if (!_loaded) return;
    try {
      await _repository.flush();
      // Export what is actually saved for THIS account.
      final saved = await _repository.load(widget.user.id, defaultTheme: _settings.themeMode);
      final counts = DataCounts.of(saved);
      if (counts.isEmpty) {
        _snack('There is nothing to export yet. Add academic records or complete your profile first.');
        return;
      }
      final file = DataTransfer.buildExport(saved);
      final done = await widget.files.saveJsonFile(file.fileName, file.bytes);
      _snack(
        done
            ? 'Exported ${describeCounts(file.counts)} (${file.fileName}).'
            : 'Export cancelled.',
        seconds: 6,
      );
    } catch (e) {
      if (!mounted) return;
      await showDataErrorDialog(context, title: 'Export failed', error: e);
    }
  }

  // Retained data-maintenance implementation; no UI action exposes this flow.
  // ignore: unused_element
  void _loadSampleData() {
    if (_hasDemoData) return;
    final now = DateTime.now();
    _mutate(() {
      _terms.add(
        AcademicTerm(
          name: 'Sample - 1st Year - 1st Term',
          isDemo: true,
          courses: [
            Course(
              code: 'BTVTED-ICT 101',
              title: 'Hardware Servicing',
              units: 3,
              assessments: [
                Assessment(title: 'Hardware Diagnostics Quiz', scoreAchieved: 95, maxScore: 100),
                Assessment(title: 'Assembly Midterm Lab', scoreAchieved: 92, maxScore: 100),
              ],
            ),
            Course(
              code: 'HIST 101',
              title: 'Philippine History',
              units: 3,
              assessments: [
                Assessment(title: 'Research Essay', scoreAchieved: 88, maxScore: 100),
              ],
            ),
          ],
        ),
      );
      _reminders.addAll([
        Reminder(
          id: 'demo-1',
          title: 'Philippine History Essay Submission',
          courseCode: 'HIST 101',
          category: 'Assignment',
          dateTime: now.add(const Duration(days: 1)),
          isDemo: true,
        ),
        Reminder(
          id: 'demo-2',
          title: 'Hardware Servicing Midterm Exam',
          courseCode: 'BTVTED-ICT 101',
          category: 'Exam',
          dateTime: now.add(const Duration(days: 3)),
          isDemo: true,
        ),
        Reminder(
          id: 'demo-3',
          title: 'Peer Group Study Session',
          courseCode: 'STUDY',
          category: 'Group Study',
          dateTime: now.add(const Duration(days: 5)),
          isDemo: true,
        ),
      ]);
      _groups.add(
        StudyGroup(
          id: 'demo-group-1',
          name: 'Sample - BTVTED-ICT Hardware Team',
          members: ['Devon', 'Maria', 'You'],
          isDemo: true,
        ),
      );
    });
  }

  // Retained data-maintenance implementation; no UI action exposes this flow.
  // ignore: unused_element
  Future<void> _removeSampleData() async {
    final ok = await _confirm(
      title: 'Remove example records?',
      message:
          'Example terms (including anything you added inside them), example reminders and example groups will be deleted.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    _mutate(() {
      _terms.removeWhere((t) => t.isDemo);
      _reminders.removeWhere((r) => r.isDemo);
      _groups.removeWhere((g) => g.isDemo);
    });
  }

  Future<void> _logout() async {
    final ok = await _confirm(
      title: 'Log out?',
      message: 'Your data stays saved on this device and will be here when you sign back in.',
      confirmLabel: 'Log out',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.flush();
      await widget.controller.signOut();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }
}
