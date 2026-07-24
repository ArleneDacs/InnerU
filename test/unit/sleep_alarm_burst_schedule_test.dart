import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';

void main() {
  group('computeSleepAlarmBurstSchedule', () {
    test('returns 11 fire times, 28 seconds apart, starting at wakesAt', () {
      final wakesAt = DateTime(2026, 7, 24, 7, 0, 0);

      final schedule = FastingNotificationService.computeSleepAlarmBurstSchedule(
        wakesAt: wakesAt,
      );

      expect(schedule.length, 11);
      expect(schedule.first, wakesAt);
      expect(schedule[1], wakesAt.add(const Duration(seconds: 28)));
      expect(schedule.last, wakesAt.add(const Duration(seconds: 280)));
    });

    test('supports a custom count and interval', () {
      final wakesAt = DateTime(2026, 7, 24, 7, 0, 0);

      final schedule = FastingNotificationService.computeSleepAlarmBurstSchedule(
        wakesAt: wakesAt,
        count: 3,
        interval: const Duration(seconds: 10),
      );

      expect(schedule, [
        wakesAt,
        wakesAt.add(const Duration(seconds: 10)),
        wakesAt.add(const Duration(seconds: 20)),
      ]);
    });
  });
}
