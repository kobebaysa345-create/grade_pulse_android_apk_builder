import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../repositories/user_data_repository.dart';

/// App-level session and theme controller. The root application overrides this
/// provider with the controller created during platform initialization.
final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  throw StateError('appControllerProvider must be overridden by GradePulseApp.');
});

/// The repository abstraction used by all application-data providers.
final userDataRepositoryProvider = Provider<UserDataRepository>((ref) {
  final controller = ref.read(appControllerProvider);
  return LocalUserDataRepository(controller.storage);
});
