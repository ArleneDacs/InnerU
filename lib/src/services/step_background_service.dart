import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class StepBackgroundService {
  StepBackgroundService._();

  static final StepBackgroundService instance = StepBackgroundService._();

  static const String _notificationChannelId = 'inneru_step_tracking';
  static const int _notificationId = 246810;

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _configured = false;
  bool _starting = false;

  Future<void> configure() async {
    if (_configured) return;

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _notificationChannelId,
        'InnerU Step Tracking',
        description: 'Keeps step tracking active in the background.',
        importance: Importance.low,
      );

      final notifications = FlutterLocalNotificationsPlugin();
      await notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: stepTrackingServiceEntryPoint,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'InnerU step tracking',
        initialNotificationContent: 'Keeping your steps updated',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.health],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: stepTrackingServiceEntryPoint,
        onBackground: stepTrackingServiceBackgroundFetch,
      ),
    );

    _configured = true;
  }

  Future<void> startTracking() async {
    await configure();
    if (_starting || await _service.isRunning()) {
      _service.invoke('stepTrackingEnabled', {'enabled': true});
      return;
    }

    _starting = true;
    try {
      if (!await _service.isRunning()) {
        await _service.startService();
      }
      _service.invoke('stepTrackingEnabled', {'enabled': true});
    } finally {
      _starting = false;
    }
  }

  Future<void> stopTracking() async {
    if (await _service.isRunning()) {
      _service.invoke('stopService');
    }
  }
}

@pragma('vm:entry-point')
Future<bool> stepTrackingServiceBackgroundFetch(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final engine = _StepTrackingEngine();
  await engine.initialize();
  await engine.syncLatestSample(service, backgroundFetch: true);
  return true;
}

@pragma('vm:entry-point')
Future<void> stepTrackingServiceEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final engine = _StepTrackingEngine();
  await engine.initialize();
  await engine.start(service);
}

class _StepTrackingEngine {
  StreamSubscription<StepCount>? _stepCountSubscription;
  Timer? _heartbeatTimer;
  ServiceInstance? _service;

  String? _userId;
  int _steps = 0;
  int _initialSteps = -1;
  int _stepCountOffset = 0;
  int _lastSyncedStepCount = -1;
  int _dailyGoal = 5000;
  bool _initialized = false;
  bool _running = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadState();
    _dailyGoal = await _loadDailyGoal();
  }

  Future<void> start(ServiceInstance service) async {
    if (_running) return;
    _running = true;
    _service = service;

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((_) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((_) async {
      await _shutdown();
      await service.stopSelf();
    });

    await _applyDailyRolloverIfNeeded();
    await _startPedometerListener();

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_running) return;
      await _applyDailyRolloverIfNeeded();
      await _persistState();
    });
  }

  Future<void> syncLatestSample(
    ServiceInstance service, {
    required bool backgroundFetch,
  }) async {
    _service = service;

    if (_userId == null) {
      await _loadState();
    }
    if (_userId == null) return;

    await _applyDailyRolloverIfNeeded();

    try {
      final stream = Pedometer.stepCountStream;
      final event = await stream.first.timeout(const Duration(seconds: 8));
      await _applyRawStepCount(
        event.steps,
        event.timeStamp,
        syncImmediately: true,
      );
    } catch (error) {
      debugPrint('Step background sync skipped: $error');
    } finally {
      if (backgroundFetch) {
        await _persistState();
      }
    }
  }

  Future<void> _startPedometerListener() async {
    await _stepCountSubscription?.cancel();

    try {
      final stream = Pedometer.stepCountStream;
      _stepCountSubscription = stream.listen(
        (event) async {
          await _applyRawStepCount(
            event.steps,
            event.timeStamp,
            syncImmediately: false,
          );
        },
        onError: (error) {
          debugPrint('Background step stream error: $error');
        },
      );
    } catch (error) {
      debugPrint('Failed to start background step listener: $error');
    }
  }

  Future<void> _applyRawStepCount(
    int currentSteps,
    DateTime eventTime, {
    required bool syncImmediately,
  }) async {
    if (_userId == null) return;

    if (_initialSteps == -1) {
      _stepCountOffset = 0;
      _initialSteps = (currentSteps - _steps).clamp(0, currentSteps);
    } else if (currentSteps < _initialSteps) {
      _stepCountOffset = _steps;
      _initialSteps = currentSteps;
    }

    var newSteps = _stepCountOffset + currentSteps - _initialSteps;
    if (newSteps < 0) newSteps = 0;
    if (newSteps == _steps) {
      return;
    }

    _steps = newSteps;

    await _persistState();

    if (syncImmediately || _shouldSyncProgress()) {
      await _syncToServer();
    }

    _service?.invoke('stepsUpdated', {
      'steps': _steps,
      'stepGoal': _dailyGoal,
    });

    WatchSyncService.instance.syncSteps(_steps, goal: _dailyGoal);
  }

  bool _shouldSyncProgress() {
    if (_lastSyncedStepCount == -1) return true;
    if (_steps == 0) return true;
    return (_steps - _lastSyncedStepCount).abs() >= 50;
  }

  Future<int> _loadDailyGoal() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return 5000;

    final prefs = await SharedPreferences.getInstance();
    final cachedGoal = prefs.getInt('daily_step_goal_$userId');
    if (cachedGoal != null && cachedGoal > 0) {
      return cachedGoal;
    }

    try {
      final userData = await UserService.getUserData();
      final rawGoal = userData['dailyStepGoal'] ?? userData['daily_step_goal'];
      final goal = rawGoal is int ? rawGoal : int.tryParse(rawGoal?.toString() ?? '');
      if (goal != null && goal > 0) {
        await prefs.setInt('daily_step_goal_$userId', goal);
        return goal;
      }
    } catch (error) {
      debugPrint('Background step goal load failed: $error');
    }

    return 5000;
  }

  Future<void> _syncToServer() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final membershipData = await CompanyMembershipService.loadForUser(userId);
      await DailyTrackerApiService.instance.upsert(
        date: formattedDate,
        stepCount: _steps,
        stepGoal: _dailyGoal,
        steps: true,
        username: AuthService.instance.currentSession?.name,
        companyId: membershipData.activeMembership?.id,
        companyCode: membershipData.activeMembership?.code,
        companyName: membershipData.activeMembership?.name,
      );

      _lastSyncedStepCount = _steps;
    } catch (error) {
      debugPrint('Background step sync failed: $error');
    }
  }

  Future<void> _applyDailyRolloverIfNeeded() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastSavedDateKey = SessionCleanupService.lastSavedDateKey(userId);
    final savedStepsKey = SessionCleanupService.savedStepsKey(userId);
    final initialStepsKey = SessionCleanupService.initialStepsKey(userId);
    final stepOffsetKey = SessionCleanupService.stepOffsetKey(userId);
    final lastSavedDate = prefs.getString(lastSavedDateKey);

    if (lastSavedDate == today) {
      return;
    }

    final previousSteps = prefs.getInt(savedStepsKey) ?? _steps;
    await _saveDailyStepsToHistory(
      userId: userId,
      steps: previousSteps,
      date: lastSavedDate,
    );

    _steps = 0;
    _initialSteps = -1;
    _stepCountOffset = 0;
    _lastSyncedStepCount = -1;

    await prefs.setInt(savedStepsKey, 0);
    await prefs.setInt(initialStepsKey, -1);
    await prefs.setInt(stepOffsetKey, 0);
    await prefs.setString(lastSavedDateKey, today);
    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
  }

  Future<void> _saveDailyStepsToHistory({
    required String userId,
    required int steps,
    required String? date,
  }) async {
    if (date == null) return;

    try {
      final membershipData = await CompanyMembershipService.loadForUser(userId);
      await DailyTrackerApiService.instance.upsert(
        date: date,
        stepCount: steps,
        stepGoal: _dailyGoal,
        steps: true,
        username: AuthService.instance.currentSession?.name,
        companyId: membershipData.activeMembership?.id,
        companyCode: membershipData.activeMembership?.code,
        companyName: membershipData.activeMembership?.name,
      );
    } catch (error) {
      debugPrint('Background step history save failed: $error');
    }
  }

  Future<void> _loadState() async {
    final session = AuthService.instance.currentSession;
    final userId = session?.id.toString();
    if (userId == null || userId.isEmpty) {
      _userId = null;
      return;
    }

    _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    _steps = prefs.getInt(SessionCleanupService.savedStepsKey(userId)) ?? 0;
    _initialSteps = prefs.getInt(SessionCleanupService.initialStepsKey(userId)) ?? -1;
    _stepCountOffset = prefs.getInt(SessionCleanupService.stepOffsetKey(userId)) ?? 0;
    _lastSyncedStepCount = _steps;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastSavedDate = prefs.getString(SessionCleanupService.lastSavedDateKey(userId));
    if (lastSavedDate != today) {
      await prefs.setString(SessionCleanupService.lastSavedDateKey(userId), today);
    }

    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
  }

  Future<void> _persistState() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await prefs.setInt(SessionCleanupService.savedStepsKey(userId), _steps);
      await prefs.setInt(SessionCleanupService.initialStepsKey(userId), _initialSteps);
      await prefs.setInt(SessionCleanupService.stepOffsetKey(userId), _stepCountOffset);
      await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
      await prefs.setString(SessionCleanupService.lastSavedDateKey(userId), today);
    } catch (error) {
      debugPrint('Background step state persist failed: $error');
    }
  }

  Future<void> _shutdown() async {
    _running = false;
    await _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _persistState();
  }
}
