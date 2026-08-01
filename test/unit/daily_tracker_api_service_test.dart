import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';

void main() {
  group('DailyTrackerApiService.completedActivityFields', () {
    test('includes only the activity that was completed', () {
      expect(
        DailyTrackerApiService.completedActivityFields(meditation: true),
        {'meditation': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(learning: true),
        {'learning': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(addValue: true),
        {'addValue': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(steps: true),
        {'steps': true},
      );
    });

    test('omits false activities instead of sending destructive false flags',
        () {
      expect(DailyTrackerApiService.completedActivityFields(), isEmpty);
      expect(
        DailyTrackerApiService.completedActivityFields(
          meditation: true,
          steps: false,
          learning: false,
          addValue: false,
        ),
        {'meditation': true},
      );
    });
  });
}
