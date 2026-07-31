import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/force_update_dialog.dart';

void main() {
  group('ForceUpdateDialog', () {
    testWidgets('shows the required copy and a single Update Now button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
      expect(find.text('Please update the app to continue.'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('tapping Update Now invokes the callback with the store URL',
        (tester) async {
      String? tappedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl:
                    'https://play.google.com/store/apps/details?id=com.valenin.inneru',
                onUpdateNow: (url) async => tappedUrl = url,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();

      expect(
        tappedUrl,
        'https://play.google.com/store/apps/details?id=com.valenin.inneru',
      );
    });

    testWidgets('cannot be dismissed by tapping the barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
    });
  });
}
