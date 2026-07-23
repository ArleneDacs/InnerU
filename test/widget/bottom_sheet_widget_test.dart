import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';

void main() {
  testWidgets('shows themed menu items including activity logs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => BottomSheetWidget.show(context),
                  child: const Text('Open drawer'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    expect(find.text('Activity Logs'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });
}
