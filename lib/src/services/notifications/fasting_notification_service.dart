import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class FastingNotificationService {
  FastingNotificationService._();

  static final FastingNotificationService instance =
      FastingNotificationService._();

  static const int fastingCompleteNotificationId = 4001;
  static const int fastingOngoingNotificationId = 4003;
  static const int walkTrackingNotificationId = 4002;
  static const int walkInviteAcceptedNotificationId = 4004;
  static const int exerciseCompleteNotificationId = 5003;
  static const int meditationCompleteNotificationId = 5001;
  static const int dailyMeditationReminderNotificationId = 5002;
  static const int dailySleepBedtimeReminderNotificationId = 7001;
  static const int sleepWakeNotificationId = 7002;
  static const int sleepOngoingNotificationId = 7003;
  static const int sleepAlarmBurstBaseId = 7100;
  // sleep_alarm.{wav,mp3} is the user-provided "SlowMorning" track (24s;
  // was a ~2s chime, which is why an earlier config packed 25 notifications
  // 12s apart -- trying to paper over silence between short dings with
  // sheer frequency). With a full-length track, each notification rings
  // for nearly the whole gap to the next one instead: 12 notifications 25s
  // apart (24s track + ~1s buffer so playback finishes before the next one
  // fires) covers ~4m35s with almost no silence, well under iOS's
  // 64-pending-notification cap.
  static const int sleepAlarmBurstCount = 12;
  static const Duration sleepAlarmBurstInterval = Duration(seconds: 25);
  static const String sleepAlarmPayload = 'sleep_alarm';
  static const String sleepAlarmCategoryId = 'SLEEP_ALARM';
  static const String sleepAlarmStopActionId = 'STOP_ALARM';
  static const String sleepOngoingCategoryId = 'SLEEP_ONGOING';
  static const String sleepEndSessionActionId = 'END_SLEEP';
  static const int _todoNotificationBaseId = 600000;
  static const String _channelId = 'fasting_complete_channel';
  static const String _channelName = 'Fasting reminders';
  static const String _channelDescription =
      'Alerts you when your fasting timer is complete.';
  static const String _walkTrackingChannelId = 'walk_tracking_channel';
  static const String _walkTrackingChannelName = 'Walk tracking';
  static const String _walkTrackingChannelDescription =
      'Shows when walk tracking is currently running.';
  static const String _walkInviteChannelId = 'walk_invite_updates_channel';
  static const String _walkInviteChannelName = 'Walk invite updates';
  static const String _walkInviteChannelDescription =
      'Shows when a walk invite has been accepted.';
  static const String _fastingOngoingChannelId = 'fasting_ongoing_channel';
  static const String _fastingOngoingChannelName = 'Fasting in progress';
  static const String _fastingOngoingChannelDescription =
      'Shows when a fasting timer is currently running.';
  static const String _meditationChannelId = 'meditation_reminders_channel';
  static const String _meditationChannelName = 'Meditation reminders';
  static const String _meditationChannelDescription =
      'Reminds you to meditate and alerts you when meditation is complete.';
  static const String _meditationCompleteChannelId =
      'meditation_complete_alarm_channel';
  static const String _meditationCompleteChannelName =
      'Meditation completion alerts';
  static const NotificationDetails _meditationCompleteNotificationDetails =
      NotificationDetails(
    android: AndroidNotificationDetails(
      _meditationCompleteChannelId,
      _meditationCompleteChannelName,
      channelDescription: _meditationChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );
  static const String _exerciseCompleteChannelId =
      'exercise_complete_alarm_channel';
  static const String _exerciseCompleteChannelName =
      'Exercise completion alerts';
  static const String _exerciseCompleteChannelDescription =
      'Alerts you when your exercise timer is complete.';
  static const NotificationDetails _exerciseCompleteNotificationDetails =
      NotificationDetails(
    android: AndroidNotificationDetails(
      _exerciseCompleteChannelId,
      _exerciseCompleteChannelName,
      channelDescription: _exerciseCompleteChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );
  static const String _todoChannelId = 'todo_reminders_channel';
  static const String _todoChannelName = 'To-do reminders';
  static const String _todoChannelDescription =
      'Reminds you when a to-do task is due.';
  static const String _sleepBedtimeChannelId = 'sleep_bedtime_channel';
  static const String _sleepBedtimeChannelName = 'Sleep bedtime reminders';
  static const String _sleepBedtimeChannelDescription =
      'Reminds you when it is time to prepare for sleep.';
  static const String _sleepWakeAlarmChannelId = 'sleep_wake_alarm_channel';
  static const String _sleepWakeVibrateChannelId = 'sleep_wake_vibrate_channel';
  static const String _sleepWakeSilentChannelId = 'sleep_wake_silent_channel';
  static const String _sleepWakeChannelDescription =
      'Alerts you when your sleep goal is complete.';
  static const String _sleepOngoingChannelId = 'sleep_ongoing_channel';
  static const String _sleepOngoingChannelName = 'Sleep in progress';
  static const String _sleepOngoingChannelDescription =
      'Shows when a sleep session is currently running.';
  static const NotificationDetails _walkInviteAcceptedNotificationDetails =
      NotificationDetails(
    android: AndroidNotificationDetails(
      _walkInviteChannelId,
      _walkInviteChannelName,
      channelDescription: _walkInviteChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final _sleepAlarmStoppedController = StreamController<void>.broadcast();
  final _sleepEndRequestedController = StreamController<void>.broadcast();

  Stream<void> get onSleepAlarmStopped => _sleepAlarmStoppedController.stream;
  Stream<void> get onSleepEndRequested => _sleepEndRequestedController.stream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    final initializationSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            sleepAlarmCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                sleepAlarmStopActionId,
                'Stop',
              ),
            ],
          ),
          DarwinNotificationCategory(
            sleepOngoingCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                sleepEndSessionActionId,
                'End Sleep',
                // Ends the session in the background -- shouldn't yank the
                // user into the app just to tap a lock-screen button.
                options: <DarwinNotificationActionOption>{},
              ),
            ],
          ),
        ],
      ),
    );

    await _notifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    _initialized = true;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload == sleepAlarmPayload) {
      _sleepAlarmStoppedController.add(null);
    }
    if (response.actionId == sleepEndSessionActionId) {
      _sleepEndRequestedController.add(null);
    }
  }

  /// Call once at app startup, after `initialize()`. Detects the case where
  /// tapping the sleep alarm notification is what launched the app from
  /// fully terminated -- `onDidReceiveNotificationResponse` alone doesn't
  /// reliably cover that case, only taps while already running.
  Future<void> checkLaunchNotification() async {
    await initialize();
    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchDetails?.notificationResponse?.payload == sleepAlarmPayload) {
      _sleepAlarmStoppedController.add(null);
    }
  }

  Future<void> ensurePermissions() async {
    await initialize();

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestFullScreenIntentPermission();
    await androidPlugin?.requestNotificationPolicyAccess();
    // Android 13+ denies exact alarms by default; without this request every
    // "exact" schedule falls back to inexact and alerts can arrive late,
    // unlike iOS where the same notifications fire on time.
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (error) {
      debugPrint('Exact alarm permission request failed: $error');
    }

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

  Future<void> scheduleExerciseCompleteNotification({
    required DateTime endsAt,
    required Duration goalDuration,
  }) async {
    await initialize();

    if (!endsAt.isAfter(DateTime.now())) {
      await cancelExerciseCompleteNotification();
      return;
    }

    final body =
        'Your ${formatExerciseDuration(goalDuration)} workout is done. Great job. Tap stop to save your photos.';

    try {
      await _notifications.zonedSchedule(
        id: exerciseCompleteNotificationId,
        title: 'Exercise complete',
        body: body,
        scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
        notificationDetails: _exerciseCompleteNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'exercise_complete',
      );
    } catch (error) {
      debugPrint(
        'Exact exercise notification scheduling failed, retrying inexact: $error',
      );
      await _notifications.zonedSchedule(
        id: exerciseCompleteNotificationId,
        title: 'Exercise complete',
        body: body,
        scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
        notificationDetails: _exerciseCompleteNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'exercise_complete',
      );
    }
  }

  Future<void> showExerciseCompleteNotification({
    required Duration goalDuration,
  }) async {
    await initialize();

    await _notifications.show(
      id: exerciseCompleteNotificationId,
      title: 'Exercise complete',
      body:
          'Your ${formatExerciseDuration(goalDuration)} workout is done. Great job. Tap stop to save your photos.',
      notificationDetails: _exerciseCompleteNotificationDetails,
      payload: 'exercise_complete',
    );
  }

  Future<void> cancelExerciseCompleteNotification() async {
    await initialize();
    await _notifications.cancel(id: exerciseCompleteNotificationId);
  }

  Future<void> scheduleMeditationCompleteNotification({
    required DateTime endsAt,
  }) async {
    await initialize();

    if (!endsAt.isAfter(DateTime.now())) {
      await cancelMeditationCompleteNotification();
      return;
    }

    try {
      await _notifications.zonedSchedule(
        id: meditationCompleteNotificationId,
        title: 'Meditation complete',
        body:
            'Great job. Your meditation session is over. Take a soft breath before moving on.',
        scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
        notificationDetails: _meditationCompleteNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'meditation_complete',
      );
    } catch (error) {
      debugPrint(
        'Exact meditation notification scheduling failed, retrying inexact: $error',
      );
      await _notifications.zonedSchedule(
        id: meditationCompleteNotificationId,
        title: 'Meditation complete',
        body:
            'Great job. Your meditation session is over. Take a soft breath before moving on.',
        scheduledDate: tz.TZDateTime.from(endsAt, tz.local),
        notificationDetails: _meditationCompleteNotificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'meditation_complete',
      );
    }
  }

  Future<void> showMeditationCompleteNotification() async {
    await initialize();

    await _notifications.show(
      id: meditationCompleteNotificationId,
      title: 'Meditation complete',
      body:
          'Great job. Your meditation session is over. Take a soft breath before moving on.',
      notificationDetails: _meditationCompleteNotificationDetails,
      payload: 'meditation_complete',
    );
  }

  Future<void> cancelMeditationCompleteNotification() async {
    await initialize();
    await _notifications.cancel(id: meditationCompleteNotificationId);
  }

  Future<void> scheduleDailyMeditationReminder({
    int hour = 20,
    int minute = 0,
  }) async {
    await initialize();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      id: dailyMeditationReminderNotificationId,
      title: 'Time to meditate',
      body: 'A short mindful pause can help your day feel lighter.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _meditationChannelId,
          _meditationChannelName,
          channelDescription: _meditationChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_meditation_reminder',
    );
  }

  Future<void> scheduleTodoDueNotification({
    required String taskId,
    required String title,
    required DateTime dueDate,
  }) async {
    await initialize();

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);

    if (dueDay.isBefore(today)) {
      await cancelTodoDueNotification(taskId);
      return;
    }

    var scheduledDate = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      9,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = now.add(const Duration(minutes: 1));
    }

    await _notifications.zonedSchedule(
      id: _todoNotificationId(taskId),
      title: 'Task due today',
      body: title.trim().isEmpty ? 'You have a task due today.' : title.trim(),
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _todoChannelId,
          _todoChannelName,
          channelDescription: _todoChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: null,
      payload: 'todo_due:$taskId',
    );
  }

  Future<void> cancelTodoDueNotification(String taskId) async {
    await initialize();
    await _notifications.cancel(id: _todoNotificationId(taskId));
  }

  Future<void> scheduleDailySleepBedtimeReminder({
    required int hour,
    required int minute,
  }) async {
    await initialize();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!scheduledDate.isAfter(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    try {
      await _notifications.zonedSchedule(
        id: dailySleepBedtimeReminderNotificationId,
        title: 'Bedtime reminder',
        body: 'It is time to wind down and start your sleep routine.',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _sleepBedtimeChannelId,
            _sleepBedtimeChannelName,
            channelDescription: _sleepBedtimeChannelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'sleep_bedtime_reminder',
      );
    } catch (error) {
      debugPrint(
        'Exact sleep bedtime reminder scheduling failed, retrying inexact: $error',
      );
      await _notifications.zonedSchedule(
        id: dailySleepBedtimeReminderNotificationId,
        title: 'Bedtime reminder',
        body: 'It is time to wind down and start your sleep routine.',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _sleepBedtimeChannelId,
            _sleepBedtimeChannelName,
            channelDescription: _sleepBedtimeChannelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'sleep_bedtime_reminder',
      );
    }
  }

  Future<void> cancelDailySleepBedtimeReminder() async {
    await initialize();
    await _notifications.cancel(id: dailySleepBedtimeReminderNotificationId);
  }

  Future<void> scheduleSleepWakeNotification({
    required DateTime wakesAt,
    required int goalHours,
    required String mode,
  }) async {
    await initialize();

    if (!wakesAt.isAfter(DateTime.now())) {
      await cancelSleepWakeNotification();
      return;
    }

    final normalizedMode = mode.trim().toLowerCase();
    final isSilent = normalizedMode == 'silent';
    final isVibrate = normalizedMode == 'vibrate';
    final androidDetails = AndroidNotificationDetails(
      isSilent
          ? _sleepWakeSilentChannelId
          : isVibrate
              ? _sleepWakeVibrateChannelId
              : _sleepWakeAlarmChannelId,
      isSilent
          ? 'Sleep wake silent'
          : isVibrate
              ? 'Sleep wake vibrate'
              : 'Sleep wake alarm',
      channelDescription: _sleepWakeChannelDescription,
      importance: isSilent ? Importance.low : Importance.max,
      priority: isSilent ? Priority.low : Priority.high,
      playSound: !isSilent && !isVibrate,
      enableVibration: !isSilent,
      category: AndroidNotificationCategory.alarm,
      // Shows over the lock screen like a real alarm clock instead of a
      // regular notification banner, so it's much harder to sleep through.
      fullScreenIntent: !isSilent,
      ongoing: !isSilent,
      autoCancel: isSilent,
      channelBypassDnd: !isSilent,
      audioAttributesUsage:
          isSilent ? AudioAttributesUsage.notification : AudioAttributesUsage.alarm,
    );
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: !isSilent && !isVibrate,
      interruptionLevel: isSilent
          ? InterruptionLevel.passive
          : InterruptionLevel.timeSensitive,
    );

    try {
      await _notifications.zonedSchedule(
        id: sleepWakeNotificationId,
        title: 'Wake up',
        body: 'Your $goalHours-hour sleep goal is complete.',
        scheduledDate: tz.TZDateTime.from(wakesAt, tz.local),
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: null,
        payload: 'sleep_wake',
      );
    } catch (error) {
      debugPrint(
        'Exact sleep wake notification scheduling failed, retrying inexact: $error',
      );
      await _notifications.zonedSchedule(
        id: sleepWakeNotificationId,
        title: 'Wake up',
        body: 'Your $goalHours-hour sleep goal is complete.',
        scheduledDate: tz.TZDateTime.from(wakesAt, tz.local),
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        payload: 'sleep_wake',
      );
    }
  }

  Future<void> cancelSleepWakeNotification() async {
    await initialize();
    await _notifications.cancel(id: sleepWakeNotificationId);
  }

  Future<void> scheduleSleepAlarmBurst({
    required DateTime wakesAt,
    required int goalHours,
  }) async {
    await initialize();
    await cancelSleepAlarmBurst();

    final schedule = computeSleepAlarmBurstSchedule(wakesAt: wakesAt);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _sleepWakeAlarmChannelId,
        'Sleep wake alarm',
        channelDescription: _sleepWakeChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('sleep_alarm'),
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        channelBypassDnd: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
      iOS: DarwinNotificationDetails(
        sound: 'sleep_alarm.wav',
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: sleepAlarmCategoryId,
      ),
    );

    for (var i = 0; i < schedule.length; i++) {
      final fireTime = schedule[i];
      if (!fireTime.isAfter(DateTime.now())) continue;

      try {
        await _notifications.zonedSchedule(
          id: sleepAlarmBurstBaseId + i,
          title: 'Wake up',
          body: 'Your $goalHours-hour sleep goal is complete.',
          scheduledDate: tz.TZDateTime.from(fireTime, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          matchDateTimeComponents: null,
          payload: sleepAlarmPayload,
        );
      } catch (error) {
        debugPrint(
          'Exact sleep alarm burst scheduling failed for index $i, retrying inexact: $error',
        );
        await _notifications.zonedSchedule(
          id: sleepAlarmBurstBaseId + i,
          title: 'Wake up',
          body: 'Your $goalHours-hour sleep goal is complete.',
          scheduledDate: tz.TZDateTime.from(fireTime, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: null,
          payload: sleepAlarmPayload,
        );
      }
    }
  }

  Future<void> cancelSleepAlarmBurst() async {
    await initialize();
    for (var i = 0; i < sleepAlarmBurstCount; i++) {
      await _notifications.cancel(id: sleepAlarmBurstBaseId + i);
    }
  }

  Future<void> showSleepOngoingNotification({
    required Duration elapsed,
    required Duration remaining,
    required int goalHours,
  }) async {
    await initialize();

    final body =
        'Goal: ${goalHours}h | Elapsed: ${_formatDuration(elapsed)} | Left: ${_formatDuration(remaining)}';

    try {
      await _notifications.show(
        id: sleepOngoingNotificationId,
        title: 'Sleep in progress',
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _sleepOngoingChannelId,
            _sleepOngoingChannelName,
            channelDescription: _sleepOngoingChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: false,
            category: AndroidNotificationCategory.progress,
            visibility: NotificationVisibility.public,
            actions: const [
              AndroidNotificationAction(
                sleepEndSessionActionId,
                'End Sleep',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
            interruptionLevel: InterruptionLevel.passive,
            categoryIdentifier: sleepOngoingCategoryId,
          ),
        ),
        payload: 'sleep_ongoing',
      );
    } catch (error) {
      debugPrint('Sleep ongoing notification failed: $error');
    }
  }

  Future<void> cancelSleepOngoingNotification() async {
    await initialize();
    await _notifications.cancel(id: sleepOngoingNotificationId);
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

  Future<void> showWalkInviteAcceptedNotification({
    required String walkerName,
  }) async {
    await initialize();

    await _notifications.show(
      id: walkInviteAcceptedNotificationId,
      title: 'Walk invite accepted',
      body: '$walkerName accepted your walk invite.',
      notificationDetails: _walkInviteAcceptedNotificationDetails,
      payload: 'walk_invite_accepted',
    );
  }

  Future<void> cancelWalkTrackingNotification() async {
    await initialize();
    await _notifications.cancel(id: walkTrackingNotificationId);
  }

  int _todoNotificationId(String taskId) {
    var hash = 0;
    for (final codeUnit in taskId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return _todoNotificationBaseId + (hash % 1000000);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static List<DateTime> computeSleepAlarmBurstSchedule({
    required DateTime wakesAt,
    int count = sleepAlarmBurstCount,
    Duration interval = sleepAlarmBurstInterval,
  }) {
    return List<DateTime>.generate(count, (i) => wakesAt.add(interval * i));
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
