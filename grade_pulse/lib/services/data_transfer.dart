import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import 'data_codec.dart';

/// How imported data is combined with what the account already has.
enum ImportMode { replace, merge }

/// Counts of what a [UserData] contains, for previews and result messages.
class DataCounts {
  const DataCounts({
    required this.terms,
    required this.subjects,
    required this.assessments,
    required this.reminders,
    required this.groups,
    this.hasProfile = false,
  });

  factory DataCounts.of(UserData d) {
    var subjects = 0;
    var assessments = 0;
    for (final t in d.terms) {
      subjects += t.courses.length;
      for (final c in t.courses) {
        assessments += c.assessments.length;
      }
    }
    return DataCounts(
      terms: d.terms.length,
      subjects: subjects,
      assessments: assessments,
      reminders: d.reminders.length,
      groups: d.groups.length,
      hasProfile: d.profile.hasContent,
    );
  }

  final int terms;
  final int subjects;
  final int assessments;
  final int reminders;
  final int groups;
  final bool hasProfile;

  bool get isEmpty =>
      terms == 0 &&
      subjects == 0 &&
      assessments == 0 &&
      reminders == 0 &&
      groups == 0 &&
      !hasProfile;
}

/// The outcome of applying an import to existing data (without saving it).
class ImportOutcome {
  const ImportOutcome({
    required this.data,
    required this.added,
    required this.skippedDuplicates,
    required this.keptBoth,
  });

  /// The new full data set for the account.
  final UserData data;

  /// Records that were added (in merge mode) or imported (in replace mode).
  final DataCounts added;

  /// Merge only: imported records identical to existing ones, not added again.
  final int skippedDuplicates;

  /// Merge only: imported reminders/groups whose id matched an existing record
  /// with different content. Both are kept; the imported one got a new id.
  final int keptBoth;
}

class DataTransfer {
  const DataTransfer._();

  /// A deep copy, so imported objects never alias live objects.
  static UserData copy(UserData d) => UserData.fromJson(d.toJson());

  /// Computes the result of importing [incoming] into [existing]. Neither
  /// argument is modified.
  static ImportOutcome apply(
    ImportMode mode,
    UserData existing,
    UserData incoming,
  ) {
    switch (mode) {
      case ImportMode.replace:
        final data = copy(incoming);
        return ImportOutcome(
          data: data,
          added: DataCounts.of(data),
          skippedDuplicates: 0,
          keptBoth: 0,
        );
      case ImportMode.merge:
        return _merge(existing, incoming);
    }
  }

  static String _norm(String s) => s.trim().toLowerCase();

  static ImportOutcome _merge(UserData existingIn, UserData incomingIn) {
    final result = copy(existingIn);
    final incoming = copy(incomingIn);
    var addedTerms = 0, addedCourses = 0, addedAssessments = 0;
    var addedReminders = 0, addedGroups = 0;
    var skipped = 0, keptBoth = 0;

    // Terms -> courses -> assessments, matched by name / code / content.
    for (final term in incoming.terms) {
      final match = result.terms
          .where((t) => _norm(t.name) == _norm(term.name))
          .firstOrNull;
      if (match == null) {
        result.terms.add(term);
        addedTerms += 1;
        addedCourses += term.courses.length;
        for (final c in term.courses) {
          addedAssessments += c.assessments.length;
        }
        continue;
      }
      for (final course in term.courses) {
        final courseMatch = match.courses
            .where((c) => _norm(c.code) == _norm(course.code))
            .firstOrNull;
        if (courseMatch == null) {
          match.courses.add(course);
          addedCourses += 1;
          addedAssessments += course.assessments.length;
          continue;
        }
        for (final a in course.assessments) {
          final dup = courseMatch.assessments.any(
            (x) =>
                _norm(x.title) == _norm(a.title) &&
                x.scoreAchieved == a.scoreAchieved &&
                x.maxScore == a.maxScore,
          );
          if (dup) {
            skipped += 1;
          } else {
            courseMatch.assessments.add(a);
            addedAssessments += 1;
          }
        }
      }
    }

    // Study groups are merged first so group IDs can be remapped before their
    // linked reminders/tasks are merged. This avoids orphaned group references
    // when a conflicting group ID has to be renamed.
    final groupIds = <String>{
      ...result.groups.map((g) => g.id),
      ...incoming.groups.map((g) => g.id),
    };
    final groupIdRemap = <String, String>{};
    for (final g in incoming.groups) {
      final originalId = g.id;
      final same = result.groups.where((x) => x.id == originalId).firstOrNull;
      if (same == null) {
        result.groups.add(g);
        groupIds.add(g.id);
        groupIdRemap[originalId] = g.id;
        addedGroups += 1;
      } else if (_sameGroup(same, g)) {
        groupIdRemap[originalId] = same.id;
        skipped += 1;
      } else {
        g.id = _freshId(originalId, groupIds);
        result.groups.add(g);
        groupIdRemap[originalId] = g.id;
        addedGroups += 1;
        keptBoth += 1;
      }
    }

    // Reminders are matched by ID. Remap group links before duplicate checks.
    final reminderIds = <String>{
      ...result.reminders.map((r) => r.id),
      ...incoming.reminders.map((r) => r.id),
    };
    for (final r in incoming.reminders) {
      if (r.groupId != null && groupIdRemap.containsKey(r.groupId)) {
        r.groupId = groupIdRemap[r.groupId];
      }
      final same = result.reminders.where((x) => x.id == r.id).firstOrNull;
      if (same == null) {
        result.reminders.add(r);
        reminderIds.add(r.id);
        addedReminders += 1;
      } else if (_sameReminder(same, r)) {
        skipped += 1;
      } else {
        r.id = _freshId(r.id, reminderIds);
        result.reminders.add(r);
        addedReminders += 1;
        keptBoth += 1;
      }
    }

    // Settings are never changed by a merge.
    return ImportOutcome(
      data: result,
      added: DataCounts(
        terms: addedTerms,
        subjects: addedCourses,
        assessments: addedAssessments,
        reminders: addedReminders,
        groups: addedGroups,
        hasProfile: false, // Merge deliberately preserves the existing profile.
      ),
      skippedDuplicates: skipped,
      keptBoth: keptBoth,
    );
  }

  static bool _sameReminder(Reminder a, Reminder b) =>
      a.title == b.title &&
      a.courseCode == b.courseCode &&
      a.category == b.category &&
      a.dateTime == b.dateTime &&
      a.isCompleted == b.isCompleted &&
      a.description == b.description &&
      a.priority == b.priority &&
      a.groupId == b.groupId;

  static bool _sameGroup(StudyGroup a, StudyGroup b) =>
      a.name == b.name &&
      a.courseCode == b.courseCode &&
      a.description == b.description &&
      a.createdAt == b.createdAt &&
      a.notes == b.notes &&
      a.members.length == b.members.length &&
      Iterable<int>.generate(a.members.length)
          .every((i) => a.members[i] == b.members[i]);

  static String _freshId(String base, Set<String> used) {
    var n = 1;
    var candidate = '$base-imported';
    while (used.contains(candidate)) {
      n += 1;
      candidate = '$base-imported-$n';
    }
    used.add(candidate);
    return candidate;
  }

  // ------------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------------

  /// Builds the export file for [data] and checks that it can be imported
  /// again without losing anything. Throws [JsonDataException] otherwise.
  static ExportFile buildExport(UserData data, {DateTime? now}) {
    final stamp = now ?? DateTime.now();
    final text = UserDataCodec.encode(data, exportedAt: stamp);
    final ParsedUserData back;
    try {
      back = UserDataCodec.parse(text);
    } on JsonDataException catch (e) {
      throw JsonDataException(
        'The export could not be verified, so it was not saved.',
        problems: [e.message, ...e.problems],
      );
    }
    if (jsonEncode(back.data.toJson()) != jsonEncode(data.toJson())) {
      throw const JsonDataException(
        'The export did not match your saved data when checked, so it was not saved.',
      );
    }
    return ExportFile(
      fileName: exportFileName(stamp),
      bytes: Uint8List.fromList(utf8.encode(text)),
      counts: DataCounts.of(data),
    );
  }

  static String exportFileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'grade_pulse_export_${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}.json';
  }
}

class ExportFile {
  const ExportFile({
    required this.fileName,
    required this.bytes,
    required this.counts,
  });

  final String fileName;
  final Uint8List bytes;
  final DataCounts counts;
}
