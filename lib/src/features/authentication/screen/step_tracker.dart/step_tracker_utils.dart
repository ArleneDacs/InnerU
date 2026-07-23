import 'dart:math' as math;

int resolveDisplayedStepCount({
  required int cachedSteps,
  required int remoteSteps,
}) {
  return math.max(cachedSteps, remoteSteps);
}
