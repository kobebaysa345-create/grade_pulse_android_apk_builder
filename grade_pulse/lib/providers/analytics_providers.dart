import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics.dart';
import 'user_data_provider.dart';

/// Derived academic analytics always reflect the latest shared user-data state.
final academicAnalyticsProvider = Provider<AcademicAnalytics?>((ref) {
  final data = ref.watch(userDataProvider).valueOrNull;
  if (data == null) return null;
  return AcademicAnalytics.compute(data.terms, data.settings);
});

/// A small set of shared counts useful to dashboards and future view extraction.
final userDataSummaryProvider = Provider<UserDataSummary?>((ref) {
  final data = ref.watch(userDataProvider).valueOrNull;
  if (data == null) return null;
  var subjectCount = 0;
  var assessmentCount = 0;
  for (final term in data.terms) {
    subjectCount += term.courses.length;
    for (final subject in term.courses) {
      assessmentCount += subject.assessments.length;
    }
  }
  return UserDataSummary(
    termCount: data.terms.length,
    subjectCount: subjectCount,
    assessmentCount: assessmentCount,
    pendingReminderCount: data.reminders.where((item) => !item.isCompleted).length,
    groupCount: data.groups.length,
  );
});

class UserDataSummary {
  const UserDataSummary({
    required this.termCount,
    required this.subjectCount,
    required this.assessmentCount,
    required this.pendingReminderCount,
    required this.groupCount,
  });

  final int termCount;
  final int subjectCount;
  final int assessmentCount;
  final int pendingReminderCount;
  final int groupCount;
}
