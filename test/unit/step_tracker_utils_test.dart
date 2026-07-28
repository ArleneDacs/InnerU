import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  group('shouldAutoRecenterOnSelf', () {
    test('follows the current user when no walker is focused', () {
      expect(
        shouldAutoRecenterOnSelf(focusedMemberUserId: null),
        isTrue,
      );
    });

    test('stops following self once another walker is focused', () {
      expect(
        shouldAutoRecenterOnSelf(focusedMemberUserId: 'aina-uid'),
        isFalse,
      );
    });
  });

  group('resolveAutoRecenterZoom', () {
    test('zooms in for the first fix of a tracked session', () {
      expect(
        resolveAutoRecenterZoom(isFirstFix: true, isTracking: true),
        17,
      );
    });

    test('uses a wider zoom for the first fix when not yet tracking', () {
      expect(
        resolveAutoRecenterZoom(isFirstFix: true, isTracking: false),
        16,
      );
    });

    test('preserves the current zoom on later updates so manual zoom '
        'out is not reverted', () {
      expect(
        resolveAutoRecenterZoom(isFirstFix: false, isTracking: true),
        isNull,
      );
    });
  });

  group('resolveInitialRoutePoints', () {
    test('seeds the route with the starting fix when one is available', () {
      const start = LatLng(1.35, 103.82);
      expect(resolveInitialRoutePoints(start), [start]);
    });

    test('starts with an empty route when no fix is available yet, so '
        'the walk (and its step count) can still start', () {
      expect(resolveInitialRoutePoints(null), isEmpty);
    });
  });

  group('resolveStartTrackingStatusText', () {
    test('reports normal route tracking when a fix was obtained', () {
      expect(
        resolveStartTrackingStatusText(hasInitialFix: true),
        'Tracking your route...',
      );
    });

    test('tells the user steps are tracked while GPS is still pending', () {
      expect(
        resolveStartTrackingStatusText(hasInitialFix: false),
        'Tracking your steps. Waiting for a GPS signal to draw your route...',
      );
    });
  });
}
