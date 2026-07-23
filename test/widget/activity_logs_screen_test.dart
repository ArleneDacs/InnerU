import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/activity_logs/activity_logs_screen.dart';
import 'package:selfcare_projects/src/services/activity_logs_service.dart';

void main() {
  group('ActivityLogsScreen', () {
    testWidgets('renders sample logs and summary', (tester) async {
      final snapshot = ActivityLogsSnapshot(
        generatedAt: DateTime(2026, 7, 23, 12),
        totalItems: 6,
        items: [
          const ActivityLogItem(
            kind: ActivityLogKind.meditation,
            title: 'Meditation',
            detail: 'Today',
            value: '5 mins',
          ),
          const ActivityLogItem(
            kind: ActivityLogKind.steps,
            title: 'Steps',
            detail: 'Today',
            value: '5,000',
          ),
          const ActivityLogItem(
            kind: ActivityLogKind.exercise,
            title: 'Pilates',
            detail: 'Logged today',
            value: '25 mins',
          ),
          const ActivityLogItem(
            kind: ActivityLogKind.fasting,
            title: 'Fasting',
            detail: 'Completed today',
            value: '12h',
          ),
          const ActivityLogItem(
            kind: ActivityLogKind.calories,
            title: 'Calories',
            detail: 'Today',
            value: '3,000 kcal',
          ),
          const ActivityLogItem(
            kind: ActivityLogKind.sleep,
            title: 'Sleep',
            detail: 'Completed today',
            value: '5h',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActivityLogsScreen(
            debugLoader: () async => snapshot,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activity Logs'), findsOneWidget);
      expect(find.text('6 activity logs today'), findsOneWidget);
      expect(find.text('Meditation'), findsOneWidget);
      expect(find.text('5 mins'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('5,000'), findsOneWidget);
      expect(find.text('Pilates'), findsOneWidget);
      expect(find.text('25 mins'), findsOneWidget);
      expect(find.text('Fasting'), findsOneWidget);
      expect(find.text('12h'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('3,000 kcal'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('5h'), 400);
      await tester.pumpAndSettle();
      expect(find.text('5h'), findsOneWidget);
    });
  });
}
