import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grade_pulse/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('editing profile name and email preserves account identity and sign-in', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final user = await auth.signUp(
      name: 'Alex Student',
      email: 'alex@example.com',
      password: 'securePass123',
    );

    final updated = await auth.updateProfile(
      userId: user.id,
      name: 'Alex Rivera',
      email: 'alex.rivera@example.com',
    );
    expect(updated.id, user.id);
    expect(updated.name, 'Alex Rivera');
    expect(updated.email, 'alex.rivera@example.com');
    expect(auth.restoreSession()?.id, user.id);

    await auth.signOut();
    final signedIn = await auth.signIn(
      email: 'alex.rivera@example.com',
      password: 'securePass123',
    );
    expect(signedIn.id, user.id);
    expect(signedIn.name, 'Alex Rivera');
  });

  test('profile email cannot collide with a different account', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final first = await auth.signUp(
      name: 'First Student',
      email: 'first@example.com',
      password: 'securePass123',
    );
    await auth.signOut();
    await auth.signUp(
      name: 'Second Student',
      email: 'second@example.com',
      password: 'securePass456',
    );

    await expectLater(
      auth.updateProfile(
        userId: first.id,
        name: 'First Student',
        email: 'second@example.com',
      ),
      throwsA(isA<AuthException>()),
    );
  });
}
