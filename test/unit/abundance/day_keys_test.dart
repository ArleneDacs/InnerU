import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';

void main() {
  test('dayKey buckets to local midnight', () {
    final d = DateTime(2026, 7, 17, 23, 59, 58);
    expect(dayKey(d), DateTime(2026, 7, 17));
  });

  test('isoDay pads month and day', () {
    expect(isoDay(DateTime(2026, 3, 5, 14, 30)), '2026-03-05');
  });

  test('parseDayKey round-trips isoDay', () {
    expect(parseDayKey('2026-03-05'), DateTime(2026, 3, 5));
  });

  test('addDays crosses month boundaries', () {
    expect(addDays(DateTime(2026, 1, 30), 3), DateTime(2026, 2, 2));
    expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
  });

  test('daysBetween buckets both ends and can be negative', () {
    expect(daysBetween(DateTime(2026, 7, 1, 23), DateTime(2026, 7, 3, 1)), 2);
    expect(daysBetween(DateTime(2026, 7, 3), DateTime(2026, 7, 1)), -2);
  });

  test('lastNDays yields n entries oldest first ending on end day', () {
    final days = lastNDays(3, DateTime(2026, 7, 17, 8));
    expect(days, [
      DateTime(2026, 7, 15),
      DateTime(2026, 7, 16),
      DateTime(2026, 7, 17),
    ]);
  });

  test('scoringWindow clamps to join date', () {
    final w = scoringWindow(30, DateTime(2026, 7, 10), DateTime(2026, 7, 17));
    expect(w.start, DateTime(2026, 7, 10));
    expect(w.end, DateTime(2026, 7, 17));
    expect(w.days, 8);
  });

  test('scoringWindow uses full window when join is old', () {
    final w = scoringWindow(30, DateTime(2025, 1, 1), DateTime(2026, 7, 17));
    expect(w.start, DateTime(2026, 6, 18));
    expect(w.days, 30);
  });

  test('daysUntil is negative when overdue', () {
    expect(
      daysUntil(DateTime(2026, 7, 15), now: DateTime(2026, 7, 17)),
      -2,
    );
  });
}
