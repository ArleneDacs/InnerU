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
  static const int fastingOngoingNotificationId = 4003;
  static const int walkTrackingNotificationId = 4002;
  static const String _channelId = 'fasting_complete_channel';
  static const String _channelName = 'Fasting reminders';
  static const String _channelDescription =
      'Alerts you when your fasting timer is complete.';
  static const String _walkTrackingChannelId = 'walk_tracking_channel';
  static const String _walkTrackingChannelName = 'Walk tracking';
  static const String _walkTrackingChannelDescription =
      'Shows when walk tracking is currently running.';
  static const String _fastingOngoingChannelId = 'fasting_ongoing_channel';
  static const String _fastingOngoingChannelName = 'Fasting in progress';
  static const String _fastingOngoingChannelDescription =
      'Shows when a fasting timer is currently running.';

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

    try {
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
    } catch (error) {
      debugPrint(
        'Exact fasting notification scheduling failed, retrying inexact: $error',
      );
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
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'fasting_complete',
      );
    }
  }

  Future<void> cancelFastingCompleteNotification() async {
    await initialize();
    await _notifications.cancel(id: fastingCompleteNotificationId);
  }

  Future<void> showFastingOngoingNotification({
    required int targetHours,
    required Duration elapsed,
    required Duration remaining,
  }) async {
    await initialize();

    final body =
        'Goal: ${targetHours}h | Elapsed: ${_formatDuration(elapsed)} | Left: ${_formatDuration(remaining)}';

    try {
      await _notifications.show(
        id: fastingOngoingNotificationId,
        title: 'Fasting is ongoing',
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _fastingOngoingChannelId,
            _fastingOngoingChannelName,
            channelDescription: _fastingOngoingChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: false,
            category: AndroidNotificationCategory.progress,
            visibility: NotificationVisibility.public,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
            interruptionLevel: InterruptionLevel.passive,
          ),
        ),
        payload: 'fasting_ongoing',
      );
    } catch (error) {
      debugPrint(
        'Detailed fasting ongoing notification failed, retrying simple: $error',
      );
      await _notifications.show(
        id: fastingOngoingNotificationId,
        title: 'Fasting is ongoing',
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _fastingOngoingChannelId,
            _fastingOngoingChannelName,
            channelDescription: _fastingOngoingChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        payload: 'fasting_ongoing',
      );
    }
  }

  Future<void> cancelFastingOngoingNotification() async {
    await initialize();
    await _notifications.cancel(id: fastingOngoingNotificationId);
  }

  Future<void> showWalkTrackingNotification({
    required int stepCount,
    required double distanceMeters,
    required Duration elapsed,
  }) async {
    await initialize();

    final distanceText = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';
    final elapsedText = _formatDuration(elapsed);

    await _notifications.show(
      id: walkTrackingNotificationId,
      title: 'Walk tracking is ongoing',
      body: 'Steps: $stepCount | Distance: $distanceText | Time: $elapsedText',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _walkTrackingChannelId,
          _walkTrackingChannelName,
          channelDescription: _walkTrackingChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          category: AndroidNotificationCategory.progress,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          interruptionLevel: InterruptionLevel.passive,
        ),
      ),
      payload: 'walk_tracking_ongoing',
    );
  }

  Future<void> cancelWalkTrackingNotification() async {
    await initialize();
    await _notifications.cancel(id: walkTrackingNotificationId);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
