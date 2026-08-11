import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_gallery_screen.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';

void main() {
  testWidgets('organizes exercise photos by date and opens photo details', (
    tester,
  ) async {
    final historyPage = ExerciseHistoryPage(
      page: 1,
      perPage: 18,
      hasMore: false,
      logs: [
        ExerciseHistoryLog(
          id: 'yoga-1',
          type: 'Yoga',
          durationMinutes: 30,
          durationSeconds: 1800,
          intensity: 2,
          notes: 'Slow morning flow',
          startPhotoUrl: 'http://127.0.0.1:9/yoga-start.jpg',
          endPhotoUrl: null,
          date: '2026-07-22',
          createdAt: DateTime(2026, 7, 22, 7),
        ),
        ExerciseHistoryLog(
          id: 'run-1',
          type: 'Run',
          durationMinutes: 45,
          durationSeconds: 2700,
          intensity: 3,
          notes: null,
          startPhotoUrl: null,
          endPhotoUrl: 'http://127.0.0.1:9/run-end.jpg',
          date: '2026-07-21',
          createdAt: DateTime(2026, 7, 21, 17),
        ),
      ],
    );

    Future<ExerciseHistoryPage> loadPage({
      required int page,
      required int perPage,
    }) async {
      if (page == 1) {
        return ExerciseHistoryPage(
          logs: historyPage.logs,
          page: page,
          perPage: historyPage.perPage,
          hasMore: historyPage.hasMore,
        );
      }
      return const ExerciseHistoryPage(
        logs: <ExerciseHistoryLog>[],
        page: 2,
        perPage: 18,
        hasMore: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ExerciseGalleryScreen(
          pageLoader: loadPage,
        ),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Exercise Gallery'), findsOneWidget);
    expect(find.textContaining('July 22, 2026'), findsOneWidget);
    expect(find.textContaining('July 21, 2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('exercise-gallery-yoga-1-start')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('exercise-gallery-yoga-1-start')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(ExerciseGalleryDetailScreen), findsOneWidget);
    expect(find.text('Start photo'), findsOneWidget);

    // The detail view starts with a large, square image. Scroll its lazy
    // ListView far enough to build the metadata below the fold first.
    final detailScroll = find.descendant(
      of: find.byType(ExerciseGalleryDetailScreen),
      matching: find.byType(Scrollable),
    );
    expect(detailScroll, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Slow morning flow'),
      240,
      scrollable: detailScroll,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Start photo · Yoga', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('30m 00s', skipOffstage: false), findsOneWidget);
    expect(find.text('Moderate', skipOffstage: false), findsOneWidget);
    expect(find.text('Slow morning flow', skipOffstage: false), findsOneWidget);
  });

  test('keeps gallery grouping stable for multiple photo types on one day', () {
    final log = ExerciseHistoryLog(
      id: 'both-photos',
      type: 'Cycling',
      durationMinutes: 20,
      durationSeconds: 1200,
      intensity: 1,
      notes: null,
      startPhotoUrl: 'https://example.test/start.jpg',
      endPhotoUrl: 'https://example.test/end.jpg',
      date: '2026-07-20',
      createdAt: DateTime(2026, 7, 20),
    );

    final groups = groupExerciseGalleryPhotos([log]);

    expect(groups, hasLength(1));
    expect(groups.single.dateKey, '2026-07-20');
    expect(groups.single.photos, hasLength(2));
    expect(
      groups.single.photos.map((photo) => photo.kind),
      [ExerciseGalleryPhotoKind.start, ExerciseGalleryPhotoKind.end],
    );
  });
}
