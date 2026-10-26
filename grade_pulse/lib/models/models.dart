import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Model definitions. Each model has toJson / fromJson so it can be saved, plus
// an `isDemo` flag on items that can come from the optional sample data.
// Grades, GPA and analytics are NOT stored: they are calculated from these
// records (see services/grade_math.dart and services/analytics.dart).
// ---------------------------------------------------------------------------

class Reminder {
  static const List<String> categories = [
    'Assignment',
    'Quiz',
    'Exam',
    'Project',
    'Group Study',
    'Personal',
    'Other',
  ];
  static const List<String> priorities = ['Low', 'Medium', 'High'];

  String id;
  String title;
  String courseCode;
  String category; // one of [categories]
  DateTime dateTime; // due date and optional time in the same DateTime value
  bool isCompleted;
  bool isDemo;
  String description;
  String priority;
  String? groupId; // links group tasks/sessions to a StudyGroup

  Reminder({
    required this.id,
    required this.title,
    required this.courseCode,
    required this.category,
    required this.dateTime,
    this.isCompleted = false,
    this.isDemo = false,
    this.description = '',
    this.priority = 'Medium',
    this.groupId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'courseCode': courseCode,
    'category': category,
    'dateTime': dateTime.toIso8601String(),
    'isCompleted': isCompleted,
    'isDemo': isDemo,
    'description': description,
    'priority': priority,
    if (groupId != null && groupId!.isNotEmpty) 'groupId': groupId,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final rawCategory = json['category'] as String? ?? 'Assignment';
    final rawPriority = json['priority'] as String? ?? 'Medium';
    return Reminder(
      id: json['id'] as String,
      title: json['title'] as String,
      courseCode: json['courseCode'] as String? ?? '',
      category: categories.contains(rawCategory) ? rawCategory : 'Assignment',
      dateTime: DateTime.parse(json['dateTime'] as String),
      isCompleted: json['isCompleted'] as bool? ?? false,
      isDemo: json['isDemo'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      priority: priorities.contains(rawPriority) ? rawPriority : 'Medium',
      groupId: json['groupId'] as String?,
    );
  }
}

class Assessment {
  static const List<String> categories = [
    'Quiz',
    'Assignment',
    'Exam',
    'Laboratory',
    'Project',
    'Other',
  ];

  String title;
  String category; // one of [categories]
  double scoreAchieved;
  double maxScore;

  Assessment({
    required this.title,
    required this.scoreAchieved,
    required this.maxScore,
    this.category = 'Other',
  });

  double get percentage =>
      maxScore > 0 ? (scoreAchieved / maxScore) * 100 : 0.0;

  Map<String, dynamic> toJson() => {
    'title': title,
    'category': category,
    'scoreAchieved': scoreAchieved,
    'maxScore': maxScore,
  };

  factory Assessment.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String?;
    return Assessment(
      title: json['title'] as String,
      category: categories.contains(category) ? category! : 'Other',
      scoreAchieved: (json['scoreAchieved'] as num).toDouble(),
      maxScore: (json['maxScore'] as num).toDouble(),
    );
  }
}

class Course {
  String code;
  String title;
  int units;
  List<Assessment> assessments;

  Course({
    required this.code,
    required this.title,
    required this.units,
    required this.assessments,
  });

  /// True when at least one assessment has a usable maximum score. Subjects
  /// without grades are left out of averages instead of counting as 0%.
  bool get hasGrades => assessments.any((a) => a.maxScore > 0);

  /// Points earned / points possible across all assessments, or null when the
  /// subject has no recorded assessments yet.
  double? get percent => hasGrades ? averagePercentage : null;

  double get averagePercentage {
    if (assessments.isEmpty) return 0.0;
    double totalEarned = 0;
    double totalPossible = 0;
    for (var a in assessments) {
      totalEarned += a.scoreAchieved;
      totalPossible += a.maxScore;
    }
    return totalPossible > 0 ? (totalEarned / totalPossible) * 100 : 0.0;
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'title': title,
    'units': units,
    'assessments': assessments.map((a) => a.toJson()).toList(),
  };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    units: (json['units'] as num?)?.toInt() ?? 3,
    assessments: (json['assessments'] as List<dynamic>? ?? [])
        .map((e) => Assessment.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class AcademicTerm {
  String name;
  List<Course> courses;
  bool isDemo;

  AcademicTerm({
    required this.name,
    required this.courses,
    this.isDemo = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'isDemo': isDemo,
    'courses': courses.map((c) => c.toJson()).toList(),
  };

  factory AcademicTerm.fromJson(Map<String, dynamic> json) => AcademicTerm(
    name: json['name'] as String,
    isDemo: json['isDemo'] as bool? ?? false,
    courses: (json['courses'] as List<dynamic>? ?? [])
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class StudyGroup {
  String id;
  String name;
  List<String> members;
  String notes;
  bool isDemo;
  String courseCode;
  String description;
  DateTime? createdAt;

  StudyGroup({
    required this.id,
    required this.name,
    required this.members,
    this.notes = '',
    this.isDemo = false,
    this.courseCode = '',
    this.description = '',
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'notes': notes,
    'isDemo': isDemo,
    'courseCode': courseCode,
    'description': description,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory StudyGroup.fromJson(Map<String, dynamic> json) => StudyGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    members: (json['members'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    notes: json['notes'] as String? ?? '',
    isDemo: json['isDemo'] as bool? ?? false,
    courseCode: json['courseCode'] as String? ?? '',
    description: json['description'] as String? ?? '',
    createdAt: json['createdAt'] is String
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );
}

/// One row of a grade conversion table: a percentage of at least [minPercent]
/// earns [grade] (a GPA point or a 1.0-5.0 mark, depending on the scale).
class GradeBand {
  const GradeBand(this.minPercent, this.grade);

  final double minPercent;
  final double grade;

  Map<String, dynamic> toJson() => {'min': minPercent, 'grade': grade};

  factory GradeBand.fromJson(Map<String, dynamic> json) => GradeBand(
    (json['min'] as num).toDouble(),
    (json['grade'] as num).toDouble(),
  );
}

/// Per-user settings: theme, GPA display scale, weighted-grade calculator
/// inputs, legacy target-calculator fields, and customised grade tables.
class AppSettings {
  static const List<String> gpaScales = [
    'Standard 4.0 GPA',
    'Percentage %',
    'TUP / PLM (1.0 - 5.0)',
  ];

  ThemeMode themeMode;
  String gpaScale;
  String calcCurrent;
  String calcWeight;
  String calcRemaining;
  String calcTarget;

  /// Scores for the weighted academic grade calculator, saved as text so blank
  /// inputs remain distinct from a legitimate score of zero.
  String calcQuiz;
  String calcRecitation;
  String calcGroupActivities;
  String calcSelfCheck;
  String calcUnitTest1;
  String calcUnitTest2;
  String calcTermTest;

  /// The user's overall goal as an average percentage (1-100), or null.
  double? targetPercent;

  /// Customised conversion tables by scale name. A scale with no entry uses
  /// the built-in default table (see GradeScales).
  Map<String, List<GradeBand>> gradeBands;

  AppSettings({
    this.themeMode = ThemeMode.system,
    this.gpaScale = 'Standard 4.0 GPA',
    this.calcCurrent = '',
    this.calcWeight = '',
    this.calcRemaining = '',
    this.calcTarget = '',
    this.calcQuiz = '',
    this.calcRecitation = '',
    this.calcGroupActivities = '',
    this.calcSelfCheck = '',
    this.calcUnitTest1 = '',
    this.calcUnitTest2 = '',
    this.calcTermTest = '',
    this.targetPercent,
    Map<String, List<GradeBand>>? gradeBands,
  }) : gradeBands = gradeBands ?? <String, List<GradeBand>>{};

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'gpaScale': gpaScale,
    'calcCurrent': calcCurrent,
    'calcWeight': calcWeight,
    'calcRemaining': calcRemaining,
    'calcTarget': calcTarget,
    'calcQuiz': calcQuiz,
    'calcRecitation': calcRecitation,
    'calcGroupActivities': calcGroupActivities,
    'calcSelfCheck': calcSelfCheck,
    'calcUnitTest1': calcUnitTest1,
    'calcUnitTest2': calcUnitTest2,
    'calcTermTest': calcTermTest,
    if (targetPercent != null) 'targetPercent': targetPercent,
    if (gradeBands.isNotEmpty)
      'gradeBands': gradeBands.map(
        (scale, bands) => MapEntry(scale, bands.map((b) => b.toJson()).toList()),
      ),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final scale = json['gpaScale'] as String? ?? gpaScales.first;
    final target = json['targetPercent'];
    final rawBands = json['gradeBands'];
    final bands = <String, List<GradeBand>>{};
    if (rawBands is Map) {
      rawBands.forEach((key, value) {
        if (key is String && gpaScales.contains(key) && value is List) {
          bands[key] = value
              .map((e) => GradeBand.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      });
    }
    return AppSettings(
      themeMode: parseThemeMode(json['themeMode'] as String?),
      gpaScale: gpaScales.contains(scale) ? scale : gpaScales.first,
      calcCurrent: json['calcCurrent'] as String? ?? '',
      calcWeight: json['calcWeight'] as String? ?? '',
      calcRemaining: json['calcRemaining'] as String? ?? '',
      calcTarget: json['calcTarget'] as String? ?? '',
      calcQuiz: json['calcQuiz'] as String? ?? '',
      calcRecitation: json['calcRecitation'] as String? ?? '',
      calcGroupActivities: json['calcGroupActivities'] as String? ?? '',
      calcSelfCheck: json['calcSelfCheck'] as String? ?? '',
      calcUnitTest1: json['calcUnitTest1'] as String? ?? '',
      calcUnitTest2: json['calcUnitTest2'] as String? ?? '',
      calcTermTest: json['calcTermTest'] as String? ?? '',
      targetPercent: target is num ? target.toDouble() : null,
      gradeBands: bands,
    );
  }

  static ThemeMode parseThemeMode(String? name) => ThemeMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => ThemeMode.system,
  );
}

/// Non-sensitive, user-editable academic profile metadata. Authentication identity
/// (name/email used to sign in) is managed separately by [AuthService] and is
/// deliberately never included in backup JSON.
class StudentProfile {
  String school;
  String program;
  String yearLevel;
  String studentInfo;

  StudentProfile({
    this.school = '',
    this.program = '',
    this.yearLevel = '',
    this.studentInfo = '',
  });

  bool get hasContent =>
      school.trim().isNotEmpty ||
      program.trim().isNotEmpty ||
      yearLevel.trim().isNotEmpty ||
      studentInfo.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'school': school,
    'program': program,
    'yearLevel': yearLevel,
    'studentInfo': studentInfo,
  };

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
    school: json['school'] as String? ?? '',
    program: json['program'] as String? ?? '',
    yearLevel: json['yearLevel'] as String? ?? '',
    studentInfo: json['studentInfo'] as String? ?? '',
  );
}

/// Everything saved for one signed-in user.
class UserData {
  static const int schemaVersion = 4;

  List<AcademicTerm> terms;
  List<Reminder> reminders;
  List<StudyGroup> groups;
  AppSettings settings;
  StudentProfile profile;

  UserData({
    required this.terms,
    required this.reminders,
    required this.groups,
    required this.settings,
    StudentProfile? profile,
  }) : profile = profile ?? StudentProfile();

  factory UserData.empty({ThemeMode themeMode = ThemeMode.system}) => UserData(
    terms: <AcademicTerm>[],
    reminders: <Reminder>[],
    groups: <StudyGroup>[],
    settings: AppSettings(themeMode: themeMode),
    profile: StudentProfile(),
  );

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'terms': terms.map((t) => t.toJson()).toList(),
    'reminders': reminders.map((r) => r.toJson()).toList(),
    'groups': groups.map((g) => g.toJson()).toList(),
    'settings': settings.toJson(),
    'profile': profile.toJson(),
  };

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
    terms: (json['terms'] as List<dynamic>? ?? [])
        .map((e) => AcademicTerm.fromJson(e as Map<String, dynamic>))
        .toList(),
    reminders: (json['reminders'] as List<dynamic>? ?? [])
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList(),
    groups: (json['groups'] as List<dynamic>? ?? [])
        .map((e) => StudyGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    settings: AppSettings.fromJson(
      json['settings'] as Map<String, dynamic>? ?? <String, dynamic>{},
    ),
    profile: StudentProfile.fromJson(
      json['profile'] as Map<String, dynamic>? ?? <String, dynamic>{},
    ),
  );
}
