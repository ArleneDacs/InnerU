import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_settings.dart';

void main() {
  testWidgets('sleep goal box shows default duration and opens a duration picker on tap',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SleepSettings()),
      ),
    );

    // Default sleep goal is 9 hours, shown as "9h" (no dropdown arrow, no minutes suffix).
    expect(find.text('9h'), findsOneWidget);

    await tester.tap(find.text('9h'));
    await tester.pumpAndSettle();

    // Tapping opens a bottom sheet containing the duration picker.
    expect(find.byType(CupertinoTimerPicker), findsOneWidget);
  });
}
