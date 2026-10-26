import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

/// Reactive view of the active local account. Auth mutations remain in the
/// established AppController/AuthService so existing authentication behavior
/// and tests are preserved.
final activeUserProvider = Provider((ref) {
  return ref.watch(appControllerProvider).user;
});

/// Convenience session provider for code that needs an explicit signed-in
/// account id without depending on widgets.
final activeUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(activeUserProvider);
  return user?.id;
});
