import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

int resolveDisplayedStepCount({
  required int cachedSteps,
  required int remoteSteps,
}) {
  return math.max(cachedSteps, remoteSteps);
}

/// Whether the step map should auto-recenter on the current user's own
/// live position.
///
/// The map periodically re-applies this on every location/step update
/// (about once a second while tracking). It must stand down whenever the
/// user has manually focused on another walker's marker
/// (`focusedMemberUserId != null`) — otherwise that periodic self-follow
/// yanks the camera back to the current user a moment after they center
/// on someone else.
bool shouldAutoRecenterOnSelf({required String? focusedMemberUserId}) {
  return focusedMemberUserId == null;
}

/// The zoom to apply when auto-recentering on the current user's own
/// position, or `null` if the current map zoom should be left untouched.
///
/// Only the first GPS fix of a viewing session gets an explicit zoom (to
/// give a nice initial view). Every later update returns `null` so a
/// manual pinch-zoom (e.g. zooming out to see the whole route) isn't
/// reset back on the next periodic update.
double? resolveAutoRecenterZoom({
  required bool isFirstFix,
  required bool isTracking,
}) {
  if (!isFirstFix) return null;
  return isTracking ? 17 : 16;
}

/// The route to seed a walk session with when tracking starts.
///
/// A walk must be able to start even when the very first GPS fix hasn't
/// arrived yet (weak signal, indoors, cold GPS) — step counting doesn't
/// depend on location, and the route fills itself in from the first live
/// position update once a fix does arrive (the position-update handlers
/// already treat an empty route as "no previous point" and seed it, the
/// same way they'd seed the very first point of a route that did start
/// with a fix).
List<LatLng> resolveInitialRoutePoints(LatLng? startPoint) {
  return startPoint == null ? const <LatLng>[] : <LatLng>[startPoint];
}

/// The status message shown right after tracking starts, depending on
/// whether an initial GPS fix was available yet.
String resolveStartTrackingStatusText({required bool hasInitialFix}) {
  return hasInitialFix
      ? 'Tracking your route...'
      : 'Tracking your steps. Waiting for a GPS signal to draw your route...';
}
