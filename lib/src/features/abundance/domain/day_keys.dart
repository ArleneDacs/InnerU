/// Every daily record in the abundance feature — a merit log, a completion,
/// a snapshot — is keyed to a "day key": the LOCAL calendar date rendered
/// `yyyy-MM-dd`, matching how the rest of InnerU keys daily records.
/// (A12-Tracker used UTC buckets; on a phone the user's own midnight is the
/// day boundary that matters.)
library;

/// Local midnight of the day [date] falls on.
DateTime dayKey(DateTime date) => DateTime(date.year, date.month, date.day);

/// Today's local midnight.
DateTime today() => dayKey(DateTime.now());

/// [days] whole days after [date]'s day. The constructor normalises
/// overflow, so this is safe across month ends and DST transitions.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Whole days from [from] to [to]; both are bucketed first. Negative when
/// [to] is earlier. Rounded via hours so a DST-shortened day still counts
/// as one day.
int daysBetween(DateTime from, DateTime to) {
  final hours = dayKey(to).difference(dayKey(from)).inHours;
  return (hours / 24).round();
}

/// Stable `yyyy-MM-dd` key — used as Firestore doc-id fragments and for
/// lexicographic date comparison.
String isoDay(DateTime date) {
  final d = dayKey(date);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Inverse of [isoDay]. `DateTime.parse` of a date-only string is local.
DateTime parseDayKey(String key) => dayKey(DateTime.parse(key));

/// The inclusive list of day keys in a window ending on [end]'s day.
/// `lastNDays(30)` yields 30 entries, oldest first, the last being today.
List<DateTime> lastNDays(int n, [DateTime? end]) {
  final last = dayKey(end ?? DateTime.now());
  return List.generate(n, (i) => addDays(last, i - (n - 1)));
}

/// The window a trailing-N-day metric covers, clamped so it never predates
/// the user joining.
typedef ScoringWindow = ({DateTime start, DateTime end, int days});

ScoringWindow scoringWindow(int windowDays, DateTime joinedAt,
    [DateTime? end]) {
  final endKey = dayKey(end ?? DateTime.now());
  final naiveStart = addDays(endKey, -(windowDays - 1));
  final joinKey = dayKey(joinedAt);
  final start = joinKey.isAfter(naiveStart) ? joinKey : naiveStart;
  return (start: start, end: endKey, days: daysBetween(start, endKey) + 1);
}

/// Negative when overdue. Drives goal-deadline badges.
int daysUntil(DateTime target, {DateTime? now}) =>
    daysBetween(now ?? DateTime.now(), target);
