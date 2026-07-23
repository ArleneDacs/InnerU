import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_tracker_utils.dart';

void main() {
  group('resolveDisplayedStepCount', () {
    test('keeps cached steps when remote data is behind', () {
      expect(
        resolveDisplayedStepCount(cachedSteps: 1842, remoteSteps: 0),
        1842,
      );
    });

    test('uses the larger count when remote sync is ahead', () {
      expect(
        resolveDisplayedStepCount(cachedSteps: 1842, remoteSteps: 1901),
        1901,
      );
    });
  });
}
