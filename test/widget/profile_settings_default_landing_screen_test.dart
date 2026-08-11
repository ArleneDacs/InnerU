import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_settings.dart';
import 'package:selfcare_projects/src/services/default_landing_screen.dart';

void main() {
  testWidgets('shows the default-screen selector under Account Settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileSettings()));
    await tester.pumpAndSettle();

    expect(find.text('ACCOUNT SETTINGS'), findsOneWidget);
    expect(find.text('Default screen'), findsOneWidget);
    expect(
      find.text('Choose where InnerU opens after you sign in.'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<DefaultLandingScreen>,
      ),
      findsOneWidget,
    );
    expect(find.text('Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
