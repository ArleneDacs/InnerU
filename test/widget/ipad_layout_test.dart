import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/role_selection_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/signup.dart';

// iPad Air 11" (M3) logical resolution: 820 x 1180 @2x.
const _iPadPortrait = Size(1640, 2360);
const _iPadLandscape = Size(2360, 1640);

// Small-phone regression guard (iPhone SE class, 320 logical width).
const _smallPhone = Size(640, 1136);

Future<void> pumpAt(
  WidgetTester tester,
  Widget screen,
  Size physicalSize,
) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
}

void main() {
  final cases = <String, Size>{
    'iPad portrait': _iPadPortrait,
    'iPad landscape': _iPadLandscape,
    'small phone': _smallPhone,
  };

  for (final entry in cases.entries) {
    group('Layout on ${entry.key}', () {
      testWidgets('LoginScreen renders without layout errors',
          (tester) async {
        await pumpAt(tester, const LoginScreen(), entry.value);
        expect(find.text('InnerU'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('RoleSelectionScreen renders without layout errors',
          (tester) async {
        await pumpAt(tester, const RoleSelectionScreen(), entry.value);
        expect(find.text('Choose your role'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('SignupScreen renders without layout errors',
          (tester) async {
        await pumpAt(
          tester,
          const SignupScreen(selectedRole: 'user'),
          entry.value,
        );
        expect(find.text('Register'), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
