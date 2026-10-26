import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_data_provider.dart';

/// Reactive presentation boundary for academic records, assessments, grades, and insights.
///
/// The existing feature implementation is supplied as a child to preserve its
/// tested business logic during the incremental migration. Feature-specific
/// widgets can be moved into this file without changing the parent navigation.
class AcademicsView extends ConsumerWidget {
  const AcademicsView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(userDataProvider);
    return child;
  }
}
