import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));
  });

  group('computeSleepAlarmBurstSchedule', () {
    test('returns 12 fire times, 25 seconds apart, starting at wakesAt', () {
      final wakesAt = DateTime(2026, 7, 24, 7, 0, 0);

      final schedule =
          FastingNotificationService.computeSleepAlarmBurstSchedule(
        wakesAt: wakesAt,
      );

      expect(schedule.length, 12);
      expect(schedule.first, wakesAt);
      expect(schedule[1], wakesAt.add(const Duration(seconds: 25)));
      expect(schedule.last, wakesAt.add(const Duration(seconds: 275)));
    });

    test('supports a custom count and interval', () {
      final wakesAt = DateTime(2026, 7, 24, 7, 0, 0);

      final schedule =
          FastingNotificationService.computeSleepAlarmBurstSchedule(
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

  group('nextDailyMeditationReminderDate', () {
    test('uses the morning default for the next local occurrence', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 12, 7, 30);

      final scheduled =
          FastingNotificationService.nextDailyMeditationReminderDate(now: now);

      expect(scheduled.hour,
          FastingNotificationService.defaultDailyMeditationReminderHour);
      expect(scheduled.minute,
          FastingNotificationService.defaultDailyMeditationReminderMinute);
      expect(scheduled.day, 12);
      expect(scheduled.location.name, tz.local.name);
    });

    test('rolls to tomorrow after the morning reminder has passed', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 12, 9, 0);

      final scheduled =
          FastingNotificationService.nextDailyMeditationReminderDate(now: now);

      expect(scheduled.year, 2026);
      expect(scheduled.month, 8);
      expect(scheduled.day, 13);
      expect(scheduled.hour, 8);
      expect(scheduled.minute, 0);
    });
  });
}
