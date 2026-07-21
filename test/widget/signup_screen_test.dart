import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/signup.dart';

Future<void> pumpSignup(
  WidgetTester tester, {
  String role = 'user',
  String initialCompanyCode = '',
  bool continueWithoutCompany = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SignupScreen(
        selectedRole: role,
        initialCompanyCode: initialCompanyCode,
        continueWithoutCompany: continueWithoutCompany,
      ),
    ),
  );
  await tester.pump();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> tapRegister(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Register'));
  await tester.tap(find.text('Register'));
  await tester.pump();
}

Future<void> acceptTerms(WidgetTester tester) async {
  // The terms checkbox is the last one; the first is the no-company toggle.
  final checkbox = find.byType(Checkbox).last;
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pump();
}

void main() {
  group('SignupScreen UI', () {
    testWidgets('renders every signup field for the user role',
        (tester) async {
      await pumpSignup(tester);

      expect(field('Company Code'), findsOneWidget);
      expect(field('Username'), findsOneWidget);
      expect(field('Email'), findsOneWidget);
      expect(field('Phone Number'), findsOneWidget);
      expect(field('Password'), findsOneWidget);
      expect(field('Re-type Password'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.textContaining("I agree to InnerU's"), findsOneWidget);
    });

    testWidgets('coach role shows coach company code label', (tester) async {
      await pumpSignup(tester, role: 'coach');
      expect(field('Coach Company Code'), findsOneWidget);
    });

    testWidgets('company code input is upper-cased as you type',
        (tester) async {
      await pumpSignup(tester);

      await tester.enterText(field('Company Code'), 'acme');
      await tester.pump();

      expect(find.text('ACME'), findsOneWidget);
    });

    testWidgets('username is capped at 20 characters', (tester) async {
      await pumpSignup(tester);

      await tester.enterText(
        field('Username'),
        'a-very-long-username-that-exceeds-the-cap',
      );
      await tester.pump();

      final editable = tester.widget<EditableText>(
        find.descendant(
          of: field('Username'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.controller.text.length, 20);
    });
  });

  group('SignupScreen validation', () {
    testWidgets('blocks registration until terms are accepted',
        (tester) async {
      await pumpSignup(tester);

      await tapRegister(tester);

      expect(
        find.text('Please accept the Terms and Conditions.'),
        findsOneWidget,
      );
    });

    testWidgets('empty form shows all required-field errors', (tester) async {
      await pumpSignup(tester);
      await acceptTerms(tester);

      await tapRegister(tester);

      expect(
        find.text('Enter a company code or tick no company'),
        findsOneWidget,
      );
      expect(find.text('Username cannot be empty'), findsOneWidget);
      expect(find.text('Email cannot be empty'), findsOneWidget);
      expect(find.text('Phone number cannot be empty'), findsOneWidget);
      expect(find.text('Password cannot be empty.'), findsOneWidget);
    });

    testWidgets('rejects malformed email, phone, and weak password',
        (tester) async {
      await pumpSignup(tester, continueWithoutCompany: true);
      await acceptTerms(tester);

      await tester.enterText(field('Username'), 'karina');
      await tester.enterText(field('Email'), 'bad-email');
      await tester.enterText(field('Phone Number'), '123');
      await tester.enterText(field('Password'), 'weak');
      await tester.enterText(field('Re-type Password'), 'weak');

      await tapRegister(tester);

      expect(find.text('Invalid email format!'), findsOneWidget);
      expect(find.text('Invalid phone number!'), findsOneWidget);
      expect(
        find.text('Weak password! Use upper, lower, digit and 8+ chars.'),
        findsOneWidget,
      );
    });

    testWidgets('rejects short company code', (tester) async {
      await pumpSignup(tester);
      await acceptTerms(tester);

      await tester.enterText(field('Company Code'), 'AB');
      await tapRegister(tester);

      expect(find.text('Enter a valid company code'), findsOneWidget);
    });

    testWidgets('allows ABUNDANCE 12 short company code alias',
        (tester) async {
      await pumpSignup(tester);
      await acceptTerms(tester);

      await tester.enterText(field('Company Code'), 'A12');
      await tester.enterText(field('Username'), 'karina');
      await tester.enterText(field('Email'), 'dmkarina62@gmail.com');
      await tester.enterText(field('Phone Number'), '09171234567');
      await tester.enterText(field('Password'), 'Str0ngPass1');
      await tester.enterText(field('Re-type Password'), 'Str0ngPass1');
      await tester.pump();

      final formState = tester.state<FormState>(find.byType(Form));
      expect(formState.validate(), isTrue);
    });

    testWidgets('rejects mismatched passwords', (tester) async {
      await pumpSignup(tester, continueWithoutCompany: true);
      await acceptTerms(tester);

      await tester.enterText(field('Username'), 'karina');
      await tester.enterText(field('Email'), 'dmkarina62@gmail.com');
      await tester.enterText(field('Phone Number'), '09171234567');
      await tester.enterText(field('Password'), 'Str0ngPass1');
      await tester.enterText(field('Re-type Password'), 'Different1');

      await tapRegister(tester);

      expect(find.text('Passwords do not match!'), findsOneWidget);
    });

    testWidgets('valid input passes every validator', (tester) async {
      await pumpSignup(tester, continueWithoutCompany: true);
      await acceptTerms(tester);

      await tester.enterText(field('Username'), 'karina');
      await tester.enterText(field('Email'), 'dmkarina62@gmail.com');
      await tester.enterText(field('Phone Number'), '09171234567');
      await tester.enterText(field('Password'), 'Str0ngPass1');
      await tester.enterText(field('Re-type Password'), 'Str0ngPass1');
      await tester.pump();

      // Validate directly instead of submitting, which would call Firebase.
      final formState = tester.state<FormState>(find.byType(Form));
      expect(formState.validate(), isTrue);
    });
  });
}
