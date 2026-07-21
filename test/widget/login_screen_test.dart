import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/role_selection_screen.dart';

Future<void> pumpLogin(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-ish portrait
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
  await tester.pump();
}

void main() {
  group('LoginScreen UI', () {
    testWidgets('renders branding, form fields and actions', (tester) async {
      await pumpLogin(tester);

      expect(find.text('InnerU'), findsOneWidget);
      expect(find.text('Welcome back — sign in to continue'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text("Don't have an account?"), findsOneWidget);
      expect(find.text('Sign up.'), findsOneWidget);
    });

    testWidgets('does not show Apple sign-in on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await pumpLogin(tester);
      expect(find.text('Sign in with Apple'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('shows Apple sign-in on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await pumpLogin(tester);
      expect(find.text('Sign in with Apple'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('password visibility toggle switches obscure text',
        (tester) async {
      await pumpLogin(tester);

      final passwordField = find.widgetWithText(TextFormField, 'Password');
      await tester.enterText(passwordField, 'secret123');
      await tester.pump();

      EditableText editable() => tester.widget<EditableText>(
            find.descendant(
              of: passwordField,
              matching: find.byType(EditableText),
            ),
          );

      expect(editable().obscureText, isTrue);

      await tester.tap(
        find.descendant(of: passwordField, matching: find.byType(IconButton)),
      );
      await tester.pump();
      expect(editable().obscureText, isFalse);
    });
  });

  group('LoginScreen validation', () {
    testWidgets('empty form shows email required error', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Log in'));
      await tester.pump();

      expect(find.text('Enter your email'), findsOneWidget);
    });

    testWidgets('malformed email shows format error and blocks submit',
        (tester) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.tap(find.text('Log in'));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('accepts a well-formed email', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'dmkarina62@gmail.com',
      );
      // Only validate; do not submit (submit would hit Firebase).
      final formState = tester.state<FormState>(find.byType(Form));
      expect(formState.validate(), isTrue);
    });
  });

  group('LoginScreen navigation', () {
    testWidgets('forgot password opens reset options sheet', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.text('Reset via Email'), findsOneWidget);
      expect(find.text('Reset via Phone'), findsOneWidget);
    });

    testWidgets('sign up link opens role selection screen', (tester) async {
      await pumpLogin(tester);

      await tester.ensureVisible(find.text('Sign up.'));
      await tester.tap(find.text('Sign up.'));
      await tester.pumpAndSettle();

      expect(find.byType(RoleSelectionScreen), findsOneWidget);
      expect(find.text('Choose your role'), findsOneWidget);
    });
  });
}
