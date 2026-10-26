import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_controller.dart';
import 'providers/auth_provider.dart';
import 'providers/repository_providers.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';
import 'views/main_shell_view.dart';

/// Application root. Tests can continue to inject an initialized controller,
/// while app state and user data are exposed through Riverpod.
class GradePulseApp extends StatelessWidget {
  const GradePulseApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appControllerProvider.overrideWith((ref) => controller),
      ],
      child: const _GradePulseAppView(),
    );
  }
}

class _GradePulseAppView extends ConsumerWidget {
  const _GradePulseAppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appControllerProvider);
    final user = ref.watch(activeUserProvider);
    return MaterialApp(
      title: 'Personal Grade Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: controller.themeMode,
      home: user == null
          ? WelcomeScreen(controller: controller)
          : MainScreen(
              key: ValueKey(user.id),
              controller: controller,
              user: user,
            ),
    );
  }
}
