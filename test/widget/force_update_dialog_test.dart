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

    testWidgets('optional update can be deferred', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showOptionalUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {},
              ),
              child: const Text('open optional'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open optional'));
      await tester.pumpAndSettle();

      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Please update the app to continue.'), findsNothing);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('a failed forced store launch can be retried', (tester) async {
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {
                  attempts += 1;
                  if (attempts == 1) throw Exception('store unavailable');
                },
              ),
              child: const Text('open retry'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();

      expect(find.text('Could not open the store. Please try again.'),
          findsOneWidget);

      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('A new version is available'), findsOneWidget);
    });
  });
}
