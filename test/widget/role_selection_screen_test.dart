import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/role_selection_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/signup.dart';

Future<void> pumpRoleSelection(
  WidgetTester tester, {
  Future<bool> Function(String companyCode)? companyCodeValidator,
}) async {
  tester.view.physicalSize = const Size(1170, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: RoleSelectionScreen(
        companyCodeValidator: companyCodeValidator ?? (_) async => true,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('RoleSelectionScreen UI', () {
    testWidgets('renders role picker and continue actions', (tester) async {
      await pumpRoleSelection(tester);

      expect(find.text('Choose your role'), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Company code'), findsOneWidget);
    });

    testWidgets('company code is upper-cased as you type', (tester) async {
      await pumpRoleSelection(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Company code'),
        'acme',
      );
      await tester.pump();

      expect(find.text('ACME'), findsOneWidget);
    });
  });

  group('RoleSelectionScreen flow', () {
    testWidgets('continue with email without company choice shows a warning',
        (tester) async {
      await pumpRoleSelection(tester);

      await tester.ensureVisible(find.text('Continue with email'));
      await tester.tap(find.text('Continue with email'));
      await tester.pump();

      expect(
        find.text('Enter a company code or tick no company.'),
        findsOneWidget,
      );
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('continue with email with a company code opens the signup form',
        (tester) async {
      await pumpRoleSelection(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Company code'),
        'ACME',
      );
      await tester.ensureVisible(find.text('Continue with email'));
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();

      expect(find.byType(SignupScreen), findsOneWidget);
      // The entered company code is carried into the signup form.
      expect(find.text('ACME'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('an unknown company code shows an error and blocks signup',
        (tester) async {
      String? checkedCode;
      await pumpRoleSelection(
        tester,
        companyCodeValidator: (companyCode) async {
          checkedCode = companyCode;
          return false;
        },
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Company code'),
        'missing',
      );
      await tester.ensureVisible(find.text('Continue with email'));
      await tester.tap(find.text('Continue with email'));
      await tester.pump();

      expect(checkedCode, 'MISSING');
      expect(
        find.text(
          'Company code is invalid. Please enter a valid company code.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SignupScreen), findsNothing);
    });
  });
}
