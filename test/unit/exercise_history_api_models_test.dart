import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';

void main() {
  group('Exercise history gallery API models', () {
    test('maps a bounded response and expands only non-empty photo URLs', () {
      final page = ExerciseHistoryPage.fromJson({
        'logs': [
          {
            'id': 'exercise-1',
            'type': 'Yoga',
            'durationMinutes': '30',
            'durationSeconds': 1800,
            'intensity': 2,
            'notes': 'Morning flow',
            'startPhotoUrl': ' https://example.test/start.jpg ',
            'endPhotoUrl': '   ',
            'date': '2026-07-22',
            'createdAt': '2026-07-22T07:30:00Z',
          },
        ],
        'page': 2,
        'perPage': 18,
        'hasMore': true,
      });

      expect(page.page, 2);
      expect(page.perPage, 18);
      expect(page.hasMore, isTrue);
      expect(page.logs, hasLength(1));

      final log = page.logs.single;
      expect(log.type, 'Yoga');
      expect(log.durationMinutes, 30);
      expect(log.durationSeconds, 1800);
      expect(log.displayDate, DateTime(2026, 7, 22));
      expect(log.galleryPhotos, hasLength(1));
      expect(log.galleryPhotos.single.kind, ExerciseGalleryPhotoKind.start);
      expect(log.galleryPhotos.single.url, 'https://example.test/start.jpg');
      expect(log.galleryPhotos.single.heroTag,
          'exercise-gallery-exercise-1-start');
    });

    test('falls back to a legacy minute duration and creation date', () {
      final log = ExerciseHistoryLog.fromJson({
        'id': 'legacy-log',
        'type': 'Walk',
        'durationMinutes': 15,
        'durationSeconds': null,
        'endPhotoUrl': 'https://example.test/end.jpg',
        'createdAt': '2026-07-21T17:15:00Z',
      });

      expect(log.durationSeconds, 0);
      expect(log.durationMinutes, 15);
      expect(log.displayDate, DateTime.parse('2026-07-21T17:15:00Z'));
      expect(log.galleryPhotos.single.kind, ExerciseGalleryPhotoKind.end);
    });
  });
}
