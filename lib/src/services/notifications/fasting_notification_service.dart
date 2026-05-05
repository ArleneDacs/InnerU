import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class FastingNotificationService {
  FastingNotificationService._();

  static final FastingNotificationService instance =
      FastingNotificationService._();

  static const int fastingCompleteNotificationId = 4001;
  static const String _channelId = 'fasting_complete_channel';
  static const String _channelName = 'Fasting reminders';
  static const String _channelDescription =
      'Alerts you when your fasting timer is complete.';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _notifications.initialize(
      settings: initializationSettings,
    );
    _initialized = true;
  }

  Future<void> ensurePermissions() async {
    await initialize();

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> scheduleFastingCompleteNotification({
    required DateTime endsAt,
    required int targetHours,
  }) async {
    await initialize();

    final now = DateTime.now();
    if (!endsAt.isAfter(now)) {
      await cancelFastingCompleteNotification();
      return;
    }

    await _notifications.zonedSchedule(
      id: fastingCompleteNotificationId,
      title: 'Fasting complete',
      body:
          'Your $targetHours-hour fast is done. Time to check in and break your fast.',
      scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: null,
      payload: 'fasting_complete',
    );
  }

  Future<void> cancelFastingCompleteNotification() async {
    await initialize();
    await _notifications.cancel(id: fastingCompleteNotificationId);
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName.identifier));
    } catch (error, stackTrace) {
      debugPrint('Failed to configure local timezone: $error');
      debugPrintStack(stackTrace: stackTrace);
      tz.setLocalLocation(tz.UTC);
    }
  }
}
