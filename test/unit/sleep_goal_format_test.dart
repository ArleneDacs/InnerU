import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_settings.dart';

void main() {
  group('formatSleepGoal', () {
    test('omits minutes when the duration is a whole number of hours', () {
      expect(formatSleepGoal(const Duration(hours: 9)), '9h');
    });

    test('includes minutes when the duration has a remainder', () {
      expect(formatSleepGoal(const Duration(hours: 7, minutes: 30)), '7h 30m');
    });

    test('handles a zero duration', () {
      expect(formatSleepGoal(Duration.zero), '0h');
    });
  });
}
