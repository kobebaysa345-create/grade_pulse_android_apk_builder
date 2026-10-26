import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grade_pulse/app_controller.dart';
import 'package:grade_pulse/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the welcome screen when no account is signed in', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(prefs)..init();

    await tester.pumpWidget(GradePulseApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Grade Pulse'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
