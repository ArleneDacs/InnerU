/// The score percentage (0-100) for a single day's daily-tracker record.
///
/// [trackerData] must be an already-fetched tracker record for a specific
/// day (e.g. the `tracker` map from `DailyTrackerApiService.fetch`) — this
/// does not distinguish "no record for this day" from "record with a 0
/// score"; callers must check for a missing record themselves and only
/// call this once a record is known to exist.
int resolveDayScorePercent(Map<String, dynamic> trackerData) {
  final raw = trackerData['userTotalScore'];
  if (raw is num) {
    return raw.round().clamp(0, 100);
  }
  return 0;
}
