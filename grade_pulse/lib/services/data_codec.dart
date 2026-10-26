import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;

import '../models/models.dart';
import 'grade_math.dart';

/// Thrown when JSON text cannot be turned into valid Grade Pulse data.
/// [message] is safe to show to the user; [problems] lists each specific issue.
class JsonDataException implements Exception {
  const JsonDataException(this.message, {this.problems = const <String>[]});

  final String message;
  final List<String> problems;

  @override
  String toString() => problems.isEmpty
      ? message
      : '$message\n${problems.map((p) => '• $p').join('\n')}';
}

/// A schema upgrade step: receives a map at version N and returns it at N + 1.
typedef SchemaMigration = Map<String, dynamic> Function(
  Map<String, dynamic> json,
);

/// The result of successfully reading a JSON document.
class ParsedUserData {
  const ParsedUserData({
    required this.data,
    required this.sourceVersion,
    required this.warnings,
    this.wasMigrated = false,
    this.hasSettings = false,
    this.exportedAt,
  });

  final UserData data;

  /// The schema version found in the file, before migration.
  final int sourceVersion;

  /// Non-fatal notes (unknown fields ignored, defaults applied, ...).
  final List<String> warnings;

  /// Whether the file actually contained a `settings` object (otherwise the
  /// settings in [data] are defaults).
  final bool hasSettings;

  /// From the optional `meta.exportedAt` field of files made by Export.
  final DateTime? exportedAt;

  /// True if the file was upgraded from an older schema version.
  final bool wasMigrated;
}

/// Reads, validates, migrates and writes Grade Pulse JSON.
///
/// It reuses the existing model classes (`toJson` / `fromJson`). Everything is
/// validated first, so the models never see malformed values, and nothing is
/// returned unless the whole document is valid (no partial or silent loads).
///
/// Schema history
///  * v1 – `version`, `terms`, `reminders`, `groups`, `settings`.
///         (Exports additionally carry an optional `meta` object.)
///  * v2 – adds `assessments[].category`, `settings.calcRemaining`,
///         `settings.targetPercent` and `settings.gradeBands`. The v1 -> v2
///         migration gives every assessment a category guessed from its title.
///  * v3 – adds reminder descriptions, priorities, optional group links, and
///         study-group course/description/creation metadata.
///  * v4 – adds non-sensitive academic profile metadata (school, program, year
///         level, and student info). Authentication identity and credentials
///         are never stored in UserData or exported JSON.
///         Grades, GPA and analytics are never stored; they are calculated.
///
/// To change the schema later: bump [UserData.schemaVersion], then register a
/// function in [migrations] under the OLD version number that returns the map
/// upgraded by one version.
class UserDataCodec {
  const UserDataCodec._();

  static const int currentVersion = UserData.schemaVersion;
  static const String appId = 'grade_pulse';

  /// from-version -> function that upgrades the map to from-version + 1.
  /// Migration steps cover v1 through the current v4 schema.
  static final Map<int, SchemaMigration> migrations = <int, SchemaMigration>{
    1: _migrateV1ToV2,
    2: _migrateV2ToV3,
    3: _migrateV3ToV4,
  };

  /// v1 -> v2: every assessment gets a `category` (guessed from its title when
  /// it has none). Everything else keeps its value; new settings fields simply
  /// take their defaults. Tolerates malformed shapes (validation reports them).
  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final terms = json['terms'];
    if (terms is List) {
      out['terms'] = terms.map((t) {
        if (t is! Map) return t;
        final term = Map<String, dynamic>.from(t);
        final courses = term['courses'];
        if (courses is List) {
          term['courses'] = courses.map((c) {
            if (c is! Map) return c;
            final course = Map<String, dynamic>.from(c);
            final assessments = course['assessments'];
            if (assessments is List) {
              course['assessments'] = assessments.map((a) {
                if (a is! Map) return a;
                final assessment = Map<String, dynamic>.from(a);
                if (assessment['category'] == null) {
                  final title = assessment['title'];
                  assessment['category'] = inferCategory(title is String ? title : '');
                }
                return assessment;
              }).toList();
            }
            return course;
          }).toList();
        }
        return term;
      }).toList();
    }
    return out;
  }

  /// Best-effort category from an assessment title (used for v1 files, which
  /// had no categories). Falls back to "Other".
  static String inferCategory(String title) {
    final t = title.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(t);
    if (has(r'\blab(s|oratory|oratories)?\b')) return 'Laboratory';
    if (has(r'\bquiz(zes)?\b')) return 'Quiz';
    if (has(r'\b(project|capstone|thesis)\b')) return 'Project';
    if (has(r'\b(exam|examination|midterm|finals?|prelim|periodical)\b')) {
      return 'Exam';
    }
    if (has(r'\b(assignment|essay|homework|activity|seatwork|report|paper)\b')) {
      return 'Assignment';
    }
    return 'Other';
  }

  /// v2 -> v3 adds optional task/calendar metadata without altering IDs,
  /// dates, completion states, categories, or existing group data.
  static Map<String, dynamic> _migrateV2ToV3(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    final rawReminders = json['reminders'];
    if (rawReminders is List) {
      out['reminders'] = rawReminders.map((raw) {
        if (raw is! Map) return raw;
        final reminder = Map<String, dynamic>.from(raw);
        reminder.putIfAbsent('description', () => '');
        reminder.putIfAbsent('priority', () => 'Medium');
        return reminder;
      }).toList();
    }
    final rawGroups = json['groups'];
    if (rawGroups is List) {
      out['groups'] = rawGroups.map((raw) {
        if (raw is! Map) return raw;
        final group = Map<String, dynamic>.from(raw);
        group.putIfAbsent('courseCode', () => '');
        group.putIfAbsent('description', () => '');
        return group;
      }).toList();
    }
    return out;
  }

  /// v3 -> v4 adds an optional non-sensitive student profile object. Identity
  /// fields and credentials remain in AuthService and are never imported.
  static Map<String, dynamic> _migrateV3ToV4(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);
    out.putIfAbsent('profile', () => <String, dynamic>{});
    return out;
  }

  static const Set<String> _topKeys = {
    'version',
    'meta',
    'terms',
    'reminders',
    'groups',
    'settings',
    'profile',
  };
  static const Set<String> _dataSections = {
    'terms',
    'reminders',
    'groups',
    'settings',
    'profile',
  };
  static const Set<String> _termKeys = {'name', 'isDemo', 'courses'};
  static const Set<String> _courseKeys = {
    'code',
    'title',
    'units',
    'assessments',
  };
  static const Set<String> _assessmentKeys = {
    'title',
    'category',
    'scoreAchieved',
    'maxScore',
  };
  static const Set<String> _reminderKeys = {
    'id',
    'title',
    'courseCode',
    'category',
    'dateTime',
    'isCompleted',
    'isDemo',
    'description',
    'priority',
    'groupId',
  };
  static const Set<String> _groupKeys = {
    'id',
    'name',
    'members',
    'notes',
    'isDemo',
    'courseCode',
    'description',
    'createdAt',
  };
  static const Set<String> _settingsKeys = {
    'themeMode',
    'gpaScale',
    'calcCurrent',
    'calcWeight',
    'calcRemaining',
    'calcTarget',
    'calcQuiz',
    'calcRecitation',
    'calcGroupActivities',
    'calcSelfCheck',
    'calcUnitTest1',
    'calcUnitTest2',
    'calcTermTest',
    'targetPercent',
    'gradeBands',
  };
  static const Set<String> _profileKeys = {
    'school',
    'program',
    'yearLevel',
    'studentInfo',
  };

  // ------------------------------------------------------------------------
  // Writing
  // ------------------------------------------------------------------------

  /// Pretty-printed JSON for [data]. Only the fields of [UserData.toJson] plus
  /// a small `meta` block are written; account details (email, password hash,
  /// session) are never part of [UserData], so they cannot leak into exports.
  static String encode(UserData data, {DateTime? exportedAt}) {
    final map = <String, dynamic>{
      'version': currentVersion,
      'meta': <String, dynamic>{
        'app': appId,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      },
      ...data.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  // ------------------------------------------------------------------------
  // Reading
  // ------------------------------------------------------------------------

  /// Decodes and validates [raw]. Throws [JsonDataException] with a
  /// user-readable message if it is invalid, incomplete, corrupted or from an
  /// unsupported schema version.
  ///
  /// [migrationsOverride] and [targetVersion] exist for tests and future
  /// schema work; the app uses the defaults.
  static ParsedUserData parse(
    String raw, {
    Map<int, SchemaMigration>? migrationsOverride,
    int? targetVersion,
  }) {
    var text = raw;
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // strip a UTF-8 byte-order mark
    }
    if (text.trim().isEmpty) {
      throw const JsonDataException('The file is empty.');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw JsonDataException(
        'The file is not valid JSON, so it may be corrupted or not a Grade Pulse file.',
        problems: [e.message],
      );
    }
    return parseDecoded(
      decoded,
      migrationsOverride: migrationsOverride,
      targetVersion: targetVersion,
    );
  }

  /// Same as [parse] but for an already-decoded JSON value (used for data read
  /// back from per-user storage).
  static ParsedUserData parseDecoded(
    Object? decoded, {
    Map<int, SchemaMigration>? migrationsOverride,
    int? targetVersion,
  }) {
    final target = targetVersion ?? currentVersion;
    if (decoded is! Map) {
      throw const JsonDataException(
        'This is not Grade Pulse data: the top level of the file must be a JSON object.',
      );
    }
    var map = Map<String, dynamic>.from(decoded);
    final warnings = <String>[];

    // ---- version -------------------------------------------------------
    var version = 1;
    if (!map.containsKey('version') || map['version'] == null) {
      warnings.add('No "version" field found; treated as schema version 1.');
    } else {
      final v = map['version'];
      if (v is! num || v != v.toInt()) {
        throw const JsonDataException(
          'The "version" field must be a whole number.',
        );
      }
      version = v.toInt();
    }
    if (version < 1) {
      throw JsonDataException(
        'Unsupported schema version $version. Supported versions are 1 to $target.',
      );
    }
    if (version > target) {
      throw JsonDataException(
        'This file uses schema version $version, which is newer than this app '
        'supports (up to version $target). Update Grade Pulse and try again.',
      );
    }

    // ---- shape check ---------------------------------------------------
    if (!_dataSections.any(map.containsKey)) {
      throw const JsonDataException(
        'This file is incomplete: it has none of "terms", "reminders", '
        '"groups", "settings" or "profile", so it does not look like Grade Pulse data.',
      );
    }
    final meta = map['meta'];
    DateTime? exportedAt;
    if (meta != null) {
      if (meta is! Map) {
        throw const JsonDataException('The "meta" field must be an object.');
      }
      final app = meta['app'];
      if (app != null && app != appId) {
        throw JsonDataException(
          'This file was made by a different app ("$app"), not Grade Pulse.',
        );
      }
      final at = meta['exportedAt'];
      if (at is String) exportedAt = DateTime.tryParse(at);
    }

    // ---- migrate -------------------------------------------------------
    final steps = migrationsOverride ?? migrations;
    final sourceVersion = version;
    while (version < target) {
      final step = steps[version];
      if (step == null) {
        throw JsonDataException(
          'No migration is available from schema version $version to ${version + 1}.',
        );
      }
      try {
        map = Map<String, dynamic>.from(step(map));
      } catch (e) {
        throw JsonDataException(
          'Upgrading the file from schema version $version failed.',
          problems: ['$e'],
        );
      }
      version += 1;
      map['version'] = version;
    }

    // ---- validate sections --------------------------------------------
    final problems = <String>[];
    final unknownTop = map.keys.where((k) => !_topKeys.contains(k)).toList()
      ..sort();
    for (final k in unknownTop) {
      warnings.add('Unknown top-level field "$k" was ignored.');
    }

    final terms = _list(map, 'terms', 'terms', problems);
    final reminders = _list(map, 'reminders', 'reminders', problems);
    final groups = _list(map, 'groups', 'groups', problems);
    Map<String, dynamic>? settings;
    if (map['settings'] != null) {
      if (map['settings'] is Map) {
        settings = Map<String, dynamic>.from(map['settings'] as Map);
      } else {
        problems.add('settings: must be an object.');
      }
    }
    Map<String, dynamic>? profile;
    if (map['profile'] != null) {
      if (map['profile'] is Map) {
        profile = Map<String, dynamic>.from(map['profile'] as Map);
      } else {
        problems.add('profile: must be an object.');
      }
    }

    final unknownFields = <String>{};
    for (var i = 0; i < terms.length; i++) {
      _checkTerm(terms[i], 'terms[$i]', problems, unknownFields, warnings);
    }
    final reminderIds = <String>{};
    for (var i = 0; i < reminders.length; i++) {
      _checkReminder(
        reminders[i],
        'reminders[$i]',
        problems,
        unknownFields,
        warnings,
        reminderIds,
      );
    }
    final groupIds = <String>{};
    for (var i = 0; i < groups.length; i++) {
      _checkGroup(groups[i], 'groups[$i]', problems, unknownFields, groupIds);
    }
    for (var i = 0; i < reminders.length; i++) {
      final reminder = reminders[i];
      if (reminder is Map && reminder['groupId'] is String &&
          !(groupIds.contains(reminder['groupId'] as String))) {
        problems.add('reminders[$i].groupId: references a study group that does not exist in this file.');
      }
    }
    if (settings != null) {
      _checkSettings(settings, problems, unknownFields, warnings);
    }
    if (profile != null) {
      _checkProfile(profile, problems, unknownFields);
    }

    if (problems.isNotEmpty) {
      const maxShown = 8;
      final shown = problems.take(maxShown).toList();
      if (problems.length > maxShown) {
        shown.add('…and ${problems.length - maxShown} more problem(s).');
      }
      throw JsonDataException(
        'The file has invalid or missing data, so nothing was imported.',
        problems: shown,
      );
    }
    for (final f in (unknownFields.toList()..sort())) {
      warnings.add('Unknown field "$f" was ignored.');
    }

    // ---- build with the existing models (input is validated) ----------
    try {
      final data = UserData(
        terms: terms
            .map((e) => AcademicTerm.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        reminders: reminders.map((e) {
          final r = Map<String, dynamic>.from(e as Map);
          if (r['category'] != null &&
              !Reminder.categories.contains(r['category'])) {
            r['category'] = 'Assignment'; // already reported as a warning
          }
          return Reminder.fromJson(r);
        }).toList(),
        groups: groups
            .map((e) => StudyGroup.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        settings: AppSettings.fromJson(settings ?? <String, dynamic>{}),
        profile: StudentProfile.fromJson(profile ?? <String, dynamic>{}),
      );
      return ParsedUserData(
        data: data,
        sourceVersion: sourceVersion,
        warnings: warnings,
        wasMigrated: sourceVersion != target,
        hasSettings: settings != null,
        exportedAt: exportedAt,
      );
    } catch (e) {
      throw JsonDataException(
        'The file could not be read as Grade Pulse data.',
        problems: ['$e'],
      );
    }
  }

  // ------------------------------------------------------------------------
  // Validation helpers
  // ------------------------------------------------------------------------

  static List<dynamic> _list(
    Map<String, dynamic> map,
    String key,
    String path,
    List<String> problems,
  ) {
    final v = map[key];
    if (v == null) return const <dynamic>[];
    if (v is List) return v;
    problems.add('$path: must be a list.');
    return const <dynamic>[];
  }

  static void _unknown(
    Map<dynamic, dynamic> m,
    Set<String> known,
    String context,
    Set<String> sink,
  ) {
    for (final k in m.keys) {
      if (!known.contains(k)) sink.add('$context.$k');
    }
  }

  static bool _isNonEmptyString(Object? v) =>
      v is String && v.trim().isNotEmpty;

  static void _requireString(
    Map m,
    String key,
    String path,
    List<String> problems,
  ) {
    if (!_isNonEmptyString(m[key])) {
      problems.add('$path.$key: required text is missing or not a string.');
    }
  }

  static void _optionalString(
    Map m,
    String key,
    String path,
    List<String> problems,
  ) {
    if (m[key] != null && m[key] is! String) {
      problems.add('$path.$key: must be text.');
    }
  }

  static void _optionalBool(
    Map m,
    String key,
    String path,
    List<String> problems,
  ) {
    if (m[key] != null && m[key] is! bool) {
      problems.add('$path.$key: must be true or false.');
    }
  }

  static void _checkTerm(
    Object? e,
    String path,
    List<String> problems,
    Set<String> unknown,
    List<String> warnings,
  ) {
    if (e is! Map) {
      problems.add('$path: must be an object.');
      return;
    }
    _unknown(e, _termKeys, 'term', unknown);
    _requireString(e, 'name', path, problems);
    _optionalBool(e, 'isDemo', path, problems);
    final courses = e['courses'];
    if (courses == null) return;
    if (courses is! List) {
      problems.add('$path.courses: must be a list.');
      return;
    }
    for (var i = 0; i < courses.length; i++) {
      final c = courses[i];
      final cp = '$path.courses[$i]';
      if (c is! Map) {
        problems.add('$cp: must be an object.');
        continue;
      }
      _unknown(c, _courseKeys, 'course', unknown);
      _requireString(c, 'code', cp, problems);
      _optionalString(c, 'title', cp, problems);
      final units = c['units'];
      if (units != null) {
        if (units is! num || units != units.toInt() || units < 0) {
          problems.add('$cp.units: must be a whole number of 0 or more.');
        }
      }
      final assessments = c['assessments'];
      if (assessments == null) continue;
      if (assessments is! List) {
        problems.add('$cp.assessments: must be a list.');
        continue;
      }
      for (var j = 0; j < assessments.length; j++) {
        final a = assessments[j];
        final ap = '$cp.assessments[$j]';
        if (a is! Map) {
          problems.add('$ap: must be an object.');
          continue;
        }
        _unknown(a, _assessmentKeys, 'assessment', unknown);
        _requireString(a, 'title', ap, problems);
        final score = a['scoreAchieved'];
        final max = a['maxScore'];
        if (score is! num || !score.isFinite || score < 0) {
          problems.add('$ap.scoreAchieved: must be a number of 0 or more.');
        }
        if (max is! num || !max.isFinite || max <= 0) {
          problems.add('$ap.maxScore: must be a number greater than 0.');
        }
        if (score is num && max is num && max > 0 && score > max) {
          warnings.add('$ap: score $score is above the maximum $max.');
        }
        _optionalString(a, 'category', ap, problems);
        final cat = a['category'];
        if (cat is String && !Assessment.categories.contains(cat)) {
          warnings.add('$ap: unknown category "$cat" was changed to "Other".');
        }
      }
    }
  }

  static void _checkReminder(
    Object? e,
    String path,
    List<String> problems,
    Set<String> unknown,
    List<String> warnings,
    Set<String> ids,
  ) {
    if (e is! Map) {
      problems.add('$path: must be an object.');
      return;
    }
    _unknown(e, _reminderKeys, 'reminder', unknown);
    _requireString(e, 'id', path, problems);
    _requireString(e, 'title', path, problems);
    _optionalString(e, 'courseCode', path, problems);
    _optionalString(e, 'category', path, problems);
    _optionalString(e, 'description', path, problems);
    _optionalString(e, 'priority', path, problems);
    _optionalString(e, 'groupId', path, problems);
    _optionalBool(e, 'isCompleted', path, problems);
    _optionalBool(e, 'isDemo', path, problems);
    final id = e['id'];
    if (id is String && !ids.add(id)) {
      problems.add('$path.id: "$id" appears more than once.');
    }
    final dt = e['dateTime'];
    if (dt is! String || DateTime.tryParse(dt) == null) {
      problems.add('$path.dateTime: must be an ISO 8601 date string.');
    }
    final cat = e['category'];
    if (cat is String && !Reminder.categories.contains(cat)) {
      warnings.add(
        '$path: unknown category "$cat" was changed to "Assignment".',
      );
    }
    final priority = e['priority'];
    if (priority is String && !Reminder.priorities.contains(priority)) {
      warnings.add('$path: unknown priority "$priority" was changed to "Medium".');
    }
  }

  static void _checkGroup(
    Object? e,
    String path,
    List<String> problems,
    Set<String> unknown,
    Set<String> ids,
  ) {
    if (e is! Map) {
      problems.add('$path: must be an object.');
      return;
    }
    _unknown(e, _groupKeys, 'group', unknown);
    _requireString(e, 'id', path, problems);
    _requireString(e, 'name', path, problems);
    _optionalString(e, 'notes', path, problems);
    _optionalString(e, 'courseCode', path, problems);
    _optionalString(e, 'description', path, problems);
    _optionalBool(e, 'isDemo', path, problems);
    final createdAt = e['createdAt'];
    if (createdAt != null &&
        (createdAt is! String || DateTime.tryParse(createdAt) == null)) {
      problems.add('$path.createdAt: must be an ISO 8601 date string.');
    }
    final id = e['id'];
    if (id is String && !ids.add(id)) {
      problems.add('$path.id: "$id" appears more than once.');
    }
    final members = e['members'];
    if (members != null) {
      if (members is! List) {
        problems.add('$path.members: must be a list of names.');
      } else if (members.any((m) => m is! String)) {
        problems.add('$path.members: every member must be text.');
      }
    }
  }

  static void _checkProfile(
    Map<String, dynamic> profile,
    List<String> problems,
    Set<String> unknown,
  ) {
    _unknown(profile, _profileKeys, 'profile', unknown);
    for (final key in _profileKeys) {
      _optionalString(profile, key, 'profile', problems);
    }
  }

  static void _checkSettings(
    Map<String, dynamic> s,
    List<String> problems,
    Set<String> unknown,
    List<String> warnings,
  ) {
    _unknown(s, _settingsKeys, 'settings', unknown);
    for (final key in [
      'themeMode',
      'gpaScale',
      'calcCurrent',
      'calcWeight',
      'calcRemaining',
      'calcTarget',
      'calcQuiz',
      'calcRecitation',
      'calcGroupActivities',
      'calcSelfCheck',
      'calcUnitTest1',
      'calcUnitTest2',
      'calcTermTest',
    ]) {
      _optionalString(s, key, 'settings', problems);
    }
    final theme = s['themeMode'];
    if (theme is String && !ThemeMode.values.any((m) => m.name == theme)) {
      warnings.add('settings.themeMode "$theme" is unknown; "system" is used.');
    }
    final target = s['targetPercent'];
    if (target != null &&
        (target is! num || !target.isFinite || target <= 0 || target > 100)) {
      problems.add('settings.targetPercent: must be a number from 1 to 100.');
    }
    _checkGradeBands(s['gradeBands'], problems, warnings);
    final scale = s['gpaScale'];
    if (scale is String && !AppSettings.gpaScales.contains(scale)) {
      warnings.add(
        'settings.gpaScale "$scale" is unknown; "${AppSettings.gpaScales.first}" is used.',
      );
    }
  }

  static void _checkGradeBands(
    Object? raw,
    List<String> problems,
    List<String> warnings,
  ) {
    if (raw == null) return;
    if (raw is! Map) {
      problems.add('settings.gradeBands: must be an object.');
      return;
    }
    raw.forEach((key, value) {
      final path = 'settings.gradeBands["$key"]';
      if (key is! String ||
          !AppSettings.gpaScales.contains(key) ||
          !GradeScales.usesTable(key)) {
        warnings.add('$path: not a scale with a conversion table; it was ignored.');
        return;
      }
      if (value is! List) {
        problems.add('$path: must be a list of rows.');
        return;
      }
      final bands = <GradeBand>[];
      for (var i = 0; i < value.length; i++) {
        final row = value[i];
        if (row is! Map ||
            row['min'] is! num ||
            row['grade'] is! num ||
            !(row['min'] as num).isFinite ||
            !(row['grade'] as num).isFinite) {
          problems.add('$path[$i]: each row needs numeric "min" and "grade".');
          return;
        }
        bands.add(GradeBand(
          (row['min'] as num).toDouble(),
          (row['grade'] as num).toDouble(),
        ));
      }
      final error = GradeScales.validateBands(bands);
      if (error != null) problems.add('$path: $error');
    });
  }
}
