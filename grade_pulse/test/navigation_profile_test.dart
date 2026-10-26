import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grade_pulse/app_controller.dart';
import 'package:grade_pulse/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bottom navigation keeps all destinations and Me opens profile', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(prefs)..init();
    await controller.signUp(
      name: 'Test Student',
      email: 'test.student@example.com',
      password: 'securePass123',
    );

    await tester.pumpWidget(GradePulseApp(controller: controller));
    await tester.pumpAndSettle();

    final nav = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(nav.items.map((item) => item.label).toList(), [
      'Academics',
      'Groups',
      'Calendar',
      'Calculator',
      'Me',
    ]);

    await tester.tap(find.text('Calculator'));
    await tester.pumpAndSettle();
    expect(find.text('WEIGHTED GRADE CALCULATOR'), findsOneWidget);

    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    expect(find.text('MY PROFILE'), findsOneWidget);
    expect(find.text('Test Student'), findsAtLeastNWidgets(2));
    expect(find.text('test.student@example.com'), findsAtLeastNWidgets(2));
  });

  testWidgets('drawer exposes calculator, analytics, settings, Antigravity and logout', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(prefs)..init();
    await controller.signUp(
      name: 'Test Student',
      email: 'test.student@example.com',
      password: 'securePass123',
    );

    await tester.pumpWidget(GradePulseApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Grade Calculator'), findsOneWidget);
    expect(find.text('Academic Analytics'), findsOneWidget);
    expect(find.text('Reminders and Tasks'), findsOneWidget);
    expect(find.text('Settings and Theme'), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.text('Import JSON'), findsNothing);
    expect(find.text('Export JSON'), findsNothing);
    expect(find.text('Log Out'), findsOneWidget);

    await tester.tap(find.text('Antigravity'));
    await tester.pumpAndSettle();
    expect(find.text('JSON Management'), findsOneWidget);
    expect(find.text('Structure Preview'), findsOneWidget);
    expect(find.byKey(const ValueKey('antigravity-json-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('antigravity-source-path')), findsOneWidget);

    await tester.tap(find.byTooltip('Back to Grade Pulse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade Calculator'));
    await tester.pumpAndSettle();
    expect(find.text('WEIGHTED GRADE CALCULATOR'), findsOneWidget);
  });

  testWidgets('data settings expose only Premade for preset data management', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(prefs)..init();
    await controller.signUp(
      name: 'Test Student',
      email: 'test.student@example.com',
      password: 'securePass123',
    );

    await tester.pumpWidget(GradePulseApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Or load sample data to explore'), findsNothing);

    await tester.tap(find.byTooltip('Settings and preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Premade'), findsOneWidget);
    expect(find.text('Import from JSON file'), findsNothing);
    expect(find.text('Export data (JSON)'), findsNothing);
    expect(find.text('Remove sample data'), findsNothing);
    expect(find.text('Load sample data'), findsNothing);
  });
}
