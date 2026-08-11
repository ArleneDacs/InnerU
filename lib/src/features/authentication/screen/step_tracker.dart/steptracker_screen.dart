import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_goal_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/my_step_submissions_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_map_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_submission_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_tracker_utils.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/tracking.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/apple_health_steps_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/pending_step_sync_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/step_background_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({
    super.key,
    this.debugBackgroundStepStream,
    this.debugStepCountStream,
    this.debugRemoteTodayStepsLoader,
    this.debugUserDataLoader,
    this.debugAutoGrantStepPermission = false,
    this.debugSkipBackgroundService = false,
  });

  final Stream<int>? debugBackgroundStepStream;
  final Stream<StepCount>? debugStepCountStream;
  final Future<int> Function(String userId, String date)?
      debugRemoteTodayStepsLoader;
  final Future<Map<String, dynamic>> Function()? debugUserDataLoader;
  final bool debugAutoGrantStepPermission;
  final bool debugSkipBackgroundService;

  @override
  State<StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<StepTracker>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _maxInitialStepJump = 150;
  static const int _maxInstantStepJump = 80;
  static const double _maxStepsPerSecond = 4.5;
  static const Duration _appleHealthRefreshInterval = Duration(minutes: 5);
  static const Duration _iosLiveDisplayHold = Duration(seconds: 30);

  late AnimationController _lottieController;
  late StreamController<int> _stepStreamController;
  StreamSubscription<StepCount>? _stepCountStream;
  StreamSubscription<dynamic>? _backgroundStepUpdates;

  int _steps = 0;
  int _initialSteps = -1;
  int _lastSteps = 0;
  int _lastSyncedStepCount = -1;
  int _dailyGoal = 5000;
  int _lastRawStepCount = 0;
  int _lastAppleHealthStepCount = 0;
  int _stepCountOffset = 0;
  DateTime? _lastStepEventAt;
  bool _isWalking = false;
  bool _stepCounterInitialized = false;
  bool _hasStepPermission = false;
  bool _isDisposed = false;
  bool _stepGoalDialogVisible = false;
  bool _isAppleHealthSyncing = false;
  bool _iosLiveStepCounterStarted = false;
  bool _didRequestAppleHealthAccessThisSession = false;
  bool _appleHealthAccessDialogVisible = false;
  // Submit Steps posts a step-count photo for a coach to review, so it has
  // nothing to do if the mentee doesn't have a coach assigned yet.
  bool _hasCoach = false;
  String? _stepPermissionMessage;
  DateTime? _appleHealthLastSyncedAt;
  int? _lastPedometerRawSteps;
  Timer? _checkTimer;
  Timer? _statePersistTimer;
  Timer? _appleHealthRefreshTimer;
  final ImagePicker _memoryPicker = ImagePicker();
  final DailyTrackerApiService _dailyTrackerApiService =
      DailyTrackerApiService.instance;

  String? get _currentUserId =>
      AuthService.instance.currentSession?.id.toString();

  // iOS exposes motion access as sensors, while Android uses activity recognition.
  Permission get _stepPermission =>
      Platform.isIOS ? Permission.sensors : Permission.activityRecognition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lottieController = AnimationController(vsync: this);
    _stepStreamController = StreamController<int>.broadcast();
    _backgroundStepUpdates = (widget.debugBackgroundStepStream ??
            FlutterBackgroundService()
                .on('stepsUpdated')
                .map((event) => event?['steps']))
        .listen((dynamic steps) {
      if (steps is! num) return;
      unawaited(_applyExternalStepUpdate(steps.toInt()));
    });
    _initializeApp();
    _startAppleHealthRefreshTimer();
    unawaited(_loadCoachAssignment());
  }

  Future<void> _loadCoachAssignment() async {
    if (_currentUserId == null) return;
    try {
      final coaches = await CoachApiService.instance.fetchMyCoaches();
      if (!mounted || _isDisposed) return;
      setState(() {
        _hasCoach = coaches.isNotEmpty;
      });
    } catch (error) {
      debugPrint('Failed to load coach assignment: $error');
    }
  }

  Future<void> _initializeApp() async {
    await _loadDailyGoal();
    await _requestAppleHealthAccessForSession();
    await _loadSteps();
    if (Platform.isIOS && !widget.debugAutoGrantStepPermission) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _stepCounterInitialized = true;
        _hasStepPermission = _stepPermissionMessage == null;
      });
      await _startIosLiveStepCounter();
      await _showAppleHealthAccessDialogIfNeeded();
      return;
    }

    if (widget.debugAutoGrantStepPermission) {
      setState(() {
        _hasStepPermission = true;
      });
      _initStepCounter();
      return;
    }
    final status = await _stepPermission.status;
    if (!mounted || _isDisposed) return;

    if (status.isGranted) {
      setState(() {
        _hasStepPermission = true;
      });
      _initStepCounter();
      return;
    }

    setState(() {
      _hasStepPermission = false;
      _stepPermissionMessage =
          'Enable live step tracking when you want InnerU to count your steps.';
    });
  }

  Future<void> _loadDailyGoal() async {
    final userId = _currentUserId;
    final prefs = await SharedPreferences.getInstance();

    if (userId == null || userId.isEmpty) {
      setState(() {
        _dailyGoal = 5000;
      });
      return;
    }

    final cachedGoal = prefs.getInt('daily_step_goal_$userId');
    if (cachedGoal != null && cachedGoal > 0) {
      setState(() {
        _dailyGoal = cachedGoal;
      });
    }

    try {
      final userData = await _loadUserData();
      final dynamic rawGoal = userData['daily_step_goal'] ??
          userData['dailyStepGoal'] ??
          userData['daily_goal'] ??
          userData['dailyGoal'];
      final int? remoteGoal = rawGoal is num
          ? rawGoal.toInt()
          : int.tryParse(rawGoal?.toString() ?? '');

      if (remoteGoal != null && remoteGoal > 0 && mounted) {
        setState(() {
          _dailyGoal = remoteGoal;
        });
        await prefs.setInt('daily_step_goal_$userId', remoteGoal);
      }
    } catch (error) {
      debugPrint("Failed to load step goal: $error");
    }
  }

  Future<AppleHealthStepSyncStatus?> _loadSteps() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      _steps = 0;
      _initialSteps = -1;
      _lastRawStepCount = 0;
      return AppleHealthStepSyncStatus.skipped;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final appleHealthSync = Platform.isIOS
        ? await AppleHealthStepsService.instance.checkTodaySteps()
        : null;
    final appleHealthSteps = appleHealthSync?.steps;
    await prefs.reload();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedStepsKey = SessionCleanupService.savedStepsKey(userId);
    final initialStepsKey = SessionCleanupService.initialStepsKey(userId);
    final stepOffsetKey = SessionCleanupService.stepOffsetKey(userId);
    final lastSavedDateKey = SessionCleanupService.lastSavedDateKey(userId);
    final appleHealthLastSyncedAtKey =
        SessionCleanupService.appleHealthLastSyncedAtKey(userId);
    final lastSavedDate = prefs.getString(lastSavedDateKey);
    _appleHealthLastSyncedAt =
        _parseDateTime(prefs.getString(appleHealthLastSyncedAtKey));
    final didReadAppleHealth = appleHealthSteps != null;
    final shouldRequestHealthAccess =
        appleHealthSync?.shouldRequestAccess == true;
    final holdIosLiveDisplay = _shouldHoldIosLiveDisplay();

    // If the last saved date is not today, reset steps
    if (lastSavedDate != today) {
      final previousSteps = prefs.getInt(savedStepsKey) ?? 0;

      // Save yesterday's steps to Firestore before resetting
      await _saveDailyStepsToHistory(
        steps: previousSteps,
        date: lastSavedDate,
      );

      if (Platform.isIOS && !didReadAppleHealth) {
        _steps = prefs.getInt(savedStepsKey) ?? _steps;
        if (shouldRequestHealthAccess) {
          _lastAppleHealthStepCount = 0;
        }
        _initialSteps = -1;
        _stepCountOffset = 0;
      } else {
        // Reset steps and update last saved date.
        _steps = Platform.isIOS
            ? appleHealthSteps ?? 0
            : await _loadRemoteTodaySteps(userId, today);
        await prefs.setInt(savedStepsKey, _steps);
        await prefs.setInt(initialStepsKey, -1);
        await prefs.setString(lastSavedDateKey, today);
        await prefs.setInt(stepOffsetKey, 0);
        _initialSteps = -1;
        _stepCountOffset = 0;
      }
    } else {
      final cachedSteps = prefs.getInt(savedStepsKey) ?? 0;
      if (Platform.isIOS) {
        if (didReadAppleHealth) {
          _lastAppleHealthStepCount = cachedSteps;
        } else if (shouldRequestHealthAccess) {
          _lastAppleHealthStepCount = 0;
        }
        if (!holdIosLiveDisplay) {
          _steps = cachedSteps;
        }
      } else {
        final remoteSteps = await _loadRemoteTodaySteps(userId, today);
        _steps = resolveDisplayedStepCount(
          cachedSteps: cachedSteps,
          remoteSteps: remoteSteps,
        );
      }
      _stepCountOffset = prefs.getInt(stepOffsetKey) ?? 0;
    }
    if (Platform.isIOS && didReadAppleHealth && !holdIosLiveDisplay) {
      _lastAppleHealthStepCount = _steps;
    }

    if (Platform.isIOS) {
      _stepCounterInitialized = true;
      _hasStepPermission = !shouldRequestHealthAccess;
      _stepPermissionMessage = shouldRequestHealthAccess
          ? 'Turn on Steps access for InnerU in Apple Health so your iOS step count can sync.'
          : null;
      if (appleHealthSteps != null) {
        _appleHealthLastSyncedAt = DateTime.now();
        await prefs.setString(
          appleHealthLastSyncedAtKey,
          _appleHealthLastSyncedAt!.toIso8601String(),
        );
      }
      if (!holdIosLiveDisplay) {
        await _rebaseIosLiveStepBaseline(
          prefs: prefs,
          initialStepsKey: initialStepsKey,
          stepOffsetKey: stepOffsetKey,
        );
      }
    }

    if (!holdIosLiveDisplay) {
      _lastRawStepCount = _steps;
      _lastStepEventAt = null;
    }
    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
    WatchSyncService.instance.syncSteps(_steps, goal: _dailyGoal, force: true);

    if (mounted && !_isDisposed) {
      setState(() {
        _isWalking = false;
      });
      if (!_stepStreamController.isClosed) {
        _stepStreamController.add(_steps);
      }
    }

    return appleHealthSync?.status;
  }

  Future<void> _persistCurrentStepState() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final stepsToPersist =
          Platform.isIOS && !widget.debugAutoGrantStepPermission
              ? _lastAppleHealthStepCount
              : _steps;
      await prefs.setInt(
        SessionCleanupService.savedStepsKey(userId),
        stepsToPersist,
      );
      await prefs.setInt(
        SessionCleanupService.initialStepsKey(userId),
        _initialSteps,
      );
      await prefs.setInt(
        SessionCleanupService.stepOffsetKey(userId),
        _stepCountOffset,
      );
      await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
      await prefs.setString(
          SessionCleanupService.lastSavedDateKey(userId), today);
    } catch (error) {
      debugPrint("Failed to persist local step state: $error");
    }
  }

  Future<void> _rebaseIosLiveStepBaseline({
    required SharedPreferences prefs,
    required String initialStepsKey,
    required String stepOffsetKey,
  }) async {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;

    _stepCountOffset = _steps;
    _initialSteps = _lastPedometerRawSteps ?? -1;
    _lastRawStepCount = _steps;
    _lastStepEventAt = null;

    await prefs.setInt(initialStepsKey, _initialSteps);
    await prefs.setInt(stepOffsetKey, _stepCountOffset);
  }

  Future<void> _startIosLiveStepCounter() async {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;
    if (_iosLiveStepCounterStarted || _stepCountStream != null) return;

    var motionStatus = await Permission.sensors.status;
    if (!motionStatus.isGranted) {
      motionStatus = await Permission.sensors.request();
      if (!motionStatus.isGranted) {
        debugPrint('iOS live step counter needs Motion & Fitness permission.');
        return;
      }
    }

    _iosLiveStepCounterStarted = true;
    _stepCountStream =
        (widget.debugStepCountStream ?? Pedometer.stepCountStream).listen(
      (event) {
        unawaited(_handleIosLiveStepEvent(event));
      },
      onError: (error) {
        debugPrint('iOS live step counter unavailable: $error');
      },
    );

    _startStepWatchdogTimer();
    _startStepStateAutosave();
  }

  Future<void> _handleIosLiveStepEvent(StepCount event) async {
    if (!mounted || _isDisposed) return;

    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final initialStepsKey = SessionCleanupService.initialStepsKey(userId);
    final stepOffsetKey = SessionCleanupService.stepOffsetKey(userId);
    final currentSteps = event.steps;
    final eventTime = event.timeStamp;
    _lastPedometerRawSteps = currentSteps;

    if (_initialSteps == -1 || currentSteps < _initialSteps) {
      _stepCountOffset = _steps;
      _initialSteps = currentSteps;
      _lastRawStepCount = _steps;
      _lastStepEventAt = eventTime;
      await prefs.setInt(initialStepsKey, _initialSteps);
      await prefs.setInt(stepOffsetKey, _stepCountOffset);
      return;
    }

    var newSteps = _stepCountOffset + currentSteps - _initialSteps;
    if (newSteps < 0) newSteps = 0;

    if (_isUnrealisticStepJump(newSteps, eventTime)) {
      _stepCountOffset = _steps;
      _initialSteps = currentSteps;
      _lastRawStepCount = _steps;
      _lastStepEventAt = eventTime;
      await prefs.setInt(initialStepsKey, _initialSteps);
      await prefs.setInt(stepOffsetKey, _stepCountOffset);
      debugPrint(
        'Ignored unrealistic iOS live step jump. Rebased step baseline for $userId.',
      );
      return;
    }

    _lastStepEventAt = eventTime;
    if (newSteps != _lastRawStepCount) {
      _lastRawStepCount = newSteps;
      _updateIosLiveStepDisplay(newSteps);
    }
  }

  void _updateIosLiveStepDisplay(int newSteps) {
    if (!mounted || _isDisposed || newSteps <= _steps) return;

    setState(() {
      _isWalking = true;
      _steps = newSteps;
    });

    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(_steps);
    }

    if (_lottieController.isAnimating == false && mounted) {
      _lottieController.repeat();
    }
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  bool _shouldHoldIosLiveDisplay() {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return false;
    if (!_hasRecentIosLiveMovement()) return false;
    if (_steps <= _lastAppleHealthStepCount) return false;
    return true;
  }

  bool _hasRecentIosLiveMovement() {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return false;
    final lastStepEventAt = _lastStepEventAt;
    if (lastStepEventAt == null) return false;
    return DateTime.now().difference(lastStepEventAt) <= _iosLiveDisplayHold;
  }

  void _startAppleHealthRefreshTimer() {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;
    _appleHealthRefreshTimer?.cancel();
    _appleHealthRefreshTimer = Timer.periodic(
      _appleHealthRefreshInterval,
      (_) {
        if (!mounted || _isDisposed) return;
        unawaited(_syncAppleHealthSteps());
      },
    );
  }

  void _stopAppleHealthRefreshTimer() {
    _appleHealthRefreshTimer?.cancel();
    _appleHealthRefreshTimer = null;
  }

  Future<void> _requestAppleHealthAccessForSession() async {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;
    if (_didRequestAppleHealthAccessThisSession) return;

    _didRequestAppleHealthAccessThisSession = true;
    await AppleHealthStepsService.instance.requestStepsAccess();
  }

  Future<void> _syncAppleHealthSteps({
    bool showFeedback = false,
  }) async {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;
    if (_isAppleHealthSyncing) return;

    if (mounted && !_isDisposed) {
      setState(() {
        _isAppleHealthSyncing = true;
      });
    }

    final previousSteps = _steps;
    AppleHealthStepSyncStatus? syncStatus;
    try {
      syncStatus = await _loadSteps();
    } finally {
      if (mounted && !_isDisposed) {
        setState(() {
          _isAppleHealthSyncing = false;
        });
      }
    }

    if (!mounted || _isDisposed) return;

    if (!showFeedback) {
      if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
        await _handleStepGoalCompleted();
      }
      return;
    }

    if (_shouldRequestAppleHealthAccess(syncStatus)) {
      setState(() {
        _hasStepPermission = false;
        _stepPermissionMessage =
            'Turn on Steps access for InnerU in Apple Health so your iOS step count can sync.';
      });
      await AppleHealthStepsService.instance.requestStepsAccess();
      if (!mounted || _isDisposed) return;
      final retryStatus = await _loadSteps();
      if (!mounted || _isDisposed) return;
      if (!_shouldRequestAppleHealthAccess(retryStatus)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apple Health synced.')),
        );
        if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
          await _handleStepGoalCompleted();
        }
        return;
      }
      await _showAppleHealthAccessRequiredDialog();
      if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
        await _handleStepGoalCompleted();
      }
      return;
    }

    final message = _manualAppleHealthSyncMessage(
      syncStatus: syncStatus,
      previousSteps: previousSteps,
    );
    final showAccessHint = _shouldShowAppleHealthAccessHint(
      syncStatus: syncStatus,
      previousSteps: previousSteps,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: showAccessHint
            ? SnackBarAction(
                label: 'Check access',
                onPressed: () {
                  unawaited(_showAppleHealthAccessHelpDialog());
                },
              )
            : null,
      ),
    );

    if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
      await _handleStepGoalCompleted();
    }
  }

  String _manualAppleHealthSyncMessage({
    required AppleHealthStepSyncStatus? syncStatus,
    required int previousSteps,
  }) {
    if (syncStatus == AppleHealthStepSyncStatus.success) {
      if (_lastAppleHealthStepCount == 0) {
        return 'No Apple Health steps found yet.';
      }
      return 'Apple Health synced.';
    }

    return 'Apple Health sync requested.';
  }

  bool _shouldShowAppleHealthAccessHint({
    required AppleHealthStepSyncStatus? syncStatus,
    required int previousSteps,
  }) {
    return syncStatus == AppleHealthStepSyncStatus.success &&
        _lastAppleHealthStepCount == 0;
  }

  Future<void> _showAppleHealthAccessHelpDialog() async {
    if (!mounted || _isDisposed) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Turn on Apple Health Steps'),
          content: const Text(
            'Go to Health > tap your profile picture > Apps > InnerU > Steps, set it to Full Access, then return to InnerU and sync again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('health'),
              child: const Text('Open Health'),
            ),
          ],
        );
      },
    );

    if (!mounted || _isDisposed || action != 'health') return;
    final openedHealth = await AppleHealthStepsService.instance.openHealthApp();
    if (!mounted || _isDisposed || openedHealth) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Open Health > tap your profile picture > Apps > InnerU > Steps.',
        ),
      ),
    );
  }

  bool _shouldRequestAppleHealthAccess(AppleHealthStepSyncStatus? syncStatus) {
    return syncStatus == AppleHealthStepSyncStatus.permissionDenied ||
        syncStatus == AppleHealthStepSyncStatus.unavailable ||
        syncStatus == AppleHealthStepSyncStatus.accessMayBeDisabled;
  }

  Future<void> _showAppleHealthAccessDialogIfNeeded() async {
    if (!Platform.isIOS || widget.debugAutoGrantStepPermission) return;
    if (!mounted || _isDisposed) return;
    if (_appleHealthAccessDialogVisible) return;

    if (_stepPermissionMessage == null) {
      return;
    }

    setState(() {
      _hasStepPermission = false;
      _stepPermissionMessage =
          'Turn on Steps access for InnerU in Apple Health so your iOS step count can sync.';
    });

    await _showAppleHealthAccessRequiredDialog();
  }

  void _dismissAppleHealthAccessDialogIfReady() {
    if (!_appleHealthAccessDialogVisible) return;
    if (_stepPermissionMessage != null) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop('synced');
  }

  Future<void> _showAppleHealthAccessRequiredDialog() async {
    if (!mounted || _isDisposed) return;

    _appleHealthAccessDialogVisible = true;
    try {
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Apple Health Steps access'),
            content: const Text(
              'Steps access is turned off for InnerU. Open Health > tap your profile picture > Apps > InnerU > Steps, set it to Full Access, then return to InnerU and sync again.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final retryStatus = await _loadSteps();
                  if (!dialogContext.mounted || !mounted || _isDisposed) {
                    return;
                  }
                  if (!_shouldRequestAppleHealthAccess(retryStatus)) {
                    Navigator.of(dialogContext).pop('synced');
                  }
                },
                child: const Text('Try Again'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop('health'),
                child: const Text('Open Health'),
              ),
            ],
          );
        },
      );

      if (!mounted || _isDisposed) return;
      if (action == 'health') {
        final openedHealth =
            await AppleHealthStepsService.instance.openHealthApp();
        if (!mounted || _isDisposed) return;
        if (!openedHealth) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Open Health > tap your profile picture > Apps > InnerU > Steps.',
              ),
            ),
          );
        }
      } else if (action == 'synced') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apple Health synced.')),
        );
      }
    } finally {
      _appleHealthAccessDialogVisible = false;
    }
  }

  Future<Map<String, dynamic>> _loadUserData() async {
    final loader = widget.debugUserDataLoader;
    if (loader != null) {
      return loader();
    }
    return UserService.getUserData();
  }

  Future<void> _applyExternalStepUpdate(int newSteps) async {
    if (!mounted || _isDisposed) return;
    if (newSteps < 0 || newSteps == _steps) return;

    final previousSteps = _steps;
    setState(() {
      _isWalking = newSteps > _steps;
      _steps = newSteps;
    });

    await _persistCurrentStepState();
    if (!mounted || _isDisposed) return;

    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(_steps);
    }

    if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
      await _handleStepGoalCompleted();
    }
  }

  Future<bool> _requestPermission() async {
    if (widget.debugAutoGrantStepPermission) {
      debugPrint('Step tracking permission granted (debug override).');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasStepPermission = true;
          _stepPermissionMessage = null;
        });
      }
      return true;
    }

    var status = await _stepPermission.status;
    if (!status.isGranted) {
      status = await _stepPermission.request();
    }

    if (status.isGranted) {
      debugPrint('Step tracking permission granted.');
      if (mounted && !_isDisposed) {
        setState(() {
          _hasStepPermission = true;
          _stepPermissionMessage = null;
        });
      }
      return true;
    }

    debugPrint('Step tracking permission not granted: $status');
    if (mounted && !_isDisposed) {
      setState(() {
        _hasStepPermission = false;
        _stepPermissionMessage =
            'Motion & Fitness access was not enabled. You can still use saved step history, goals, and map features.';
      });
    }
    return false;
  }

  Future<int> _loadRemoteTodaySteps(String userId, String date) async {
    final loader = widget.debugRemoteTodayStepsLoader;
    if (loader != null) {
      return loader(userId, date);
    }

    try {
      final response = await _dailyTrackerApiService.fetch(date: date);
      final tracker = response['tracker'];
      final value = tracker is Map<String, dynamic>
          ? tracker['stepCount'] ?? tracker['step_count']
          : null;
      if (value is num && value > 0) {
        return value.toInt();
      }
    } catch (error) {
      debugPrint("Failed to load remote steps: $error");
    }
    return 0;
  }

  Future<void> _saveDailyStepsToHistory({
    required int steps,
    required String? date,
  }) async {
    if (date == null) return;

    try {
      await _dailyTrackerApiService.upsert(
        date: date,
        stepCount: steps,
        stepGoal: _dailyGoal,
        steps: true,
      );

      print("Saved $steps steps for $date");
    } catch (error) {
      debugPrint("Failed to save step history: $error");
      final userId = _currentUserId;
      if (userId != null && userId.isNotEmpty) {
        await PendingStepSyncService.instance.queueStepProgress(
          userId: userId,
          date: date,
          stepCount: steps,
          stepGoal: _dailyGoal,
          steps: true,
        );
      }
    }
  }

  void _initStepCounter() async {
    if (_stepCounterInitialized) return;
    if (Platform.isIOS && !widget.debugAutoGrantStepPermission) {
      await _loadSteps();
      return;
    }
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    setState(() {
      _stepCounterInitialized = true;
    });
    if (!widget.debugSkipBackgroundService) {
      unawaited(StepBackgroundService.instance.startTracking());
    }

    final prefs = await SharedPreferences.getInstance();
    final initialStepsKey = SessionCleanupService.initialStepsKey(userId);
    final stepOffsetKey = SessionCleanupService.stepOffsetKey(userId);
    _initialSteps = prefs.getInt(initialStepsKey) ?? -1;
    _stepCountOffset = prefs.getInt(stepOffsetKey) ?? _stepCountOffset;
    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);

    final stepStream = widget.debugStepCountStream ?? Pedometer.stepCountStream;

    _stepCountStream = stepStream.listen(
      (StepCount event) async {
        if (!mounted || _isDisposed) return;

        final currentUserId = _currentUserId;
        if (currentUserId != userId) {
          await _stopStepCounterForAccountSwitch();
          return;
        }

        final currentSteps = event.steps;
        final eventTime = event.timeStamp;

        if (_initialSteps == -1) {
          _stepCountOffset = 0;
          _initialSteps = (currentSteps - _steps).clamp(0, currentSteps);
          await prefs.setInt(initialStepsKey, _initialSteps);
          await prefs.setInt(stepOffsetKey, _stepCountOffset);
          if (!mounted || _isDisposed) return;
        } else if (currentSteps < _initialSteps) {
          _stepCountOffset = _steps;
          _initialSteps = currentSteps;
          _lastRawStepCount = _steps;
          _lastStepEventAt = null;
          await prefs.setInt(initialStepsKey, _initialSteps);
          await prefs.setInt(stepOffsetKey, _stepCountOffset);
          if (!mounted || _isDisposed) return;
        }

        var newSteps = _stepCountOffset + currentSteps - _initialSteps;

        // Prevent negative step count
        if (newSteps < 0) newSteps = 0;

        if (_isUnrealisticStepJump(newSteps, eventTime)) {
          _stepCountOffset = _steps;
          _initialSteps = currentSteps;
          _lastRawStepCount = _steps;
          _lastStepEventAt = eventTime;
          await prefs.setInt(initialStepsKey, _initialSteps);
          await prefs.setInt(stepOffsetKey, _stepCountOffset);
          debugPrint(
            'Ignored unrealistic step jump. Rebased step baseline for $userId.',
          );
          return;
        }

        _lastStepEventAt = eventTime;
        if (newSteps != _lastRawStepCount) {
          _handleRawStepCount(newSteps);
        }
      },
      onError: (error) {
        debugPrint("Step counter error: $error");
      },
    );

    _startStepWatchdogTimer();
    _startStepStateAutosave();
  }

  void _startStepWatchdogTimer() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _isDisposed) return;

      if (_steps == _lastSteps && _isWalking) {
        _setWalkingState(false);
      }
      _lastSteps = _steps;
    });
  }

  void _startStepStateAutosave() {
    _statePersistTimer?.cancel();
    _statePersistTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _isDisposed) return;
      unawaited(_persistCurrentStepState());
    });
  }

  Future<void> _stopStepCounterForAccountSwitch() async {
    unawaited(StepBackgroundService.instance.stopTracking());
    await _stepCountStream?.cancel();
    _stepCountStream = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _statePersistTimer?.cancel();
    _statePersistTimer = null;
    _stepCounterInitialized = false;
    _iosLiveStepCounterStarted = false;
    _steps = 0;
    _initialSteps = -1;
    _lastSteps = 0;
    _lastRawStepCount = 0;
    _lastPedometerRawSteps = null;
    _stepCountOffset = 0;
    _lastStepEventAt = null;
    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(0);
    }
    if (mounted && !_isDisposed) {
      setState(() {
        _isWalking = false;
      });
    }
  }

  Future<void> _pauseStepCounterForLifecycle() async {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> _stopStepCounterForLifecycle() async {
    await _stepCountStream?.cancel();
    _stepCountStream = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _statePersistTimer?.cancel();
    _statePersistTimer = null;
    _stepCounterInitialized = false;
    _iosLiveStepCounterStarted = false;
  }

  void _updateStepCount(int newSteps) async {
    if (!mounted || _isDisposed) {
      return; // Prevent updates if widget is disposed
    }

    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;

    final previousSteps = _steps;

    setState(() {
      _isWalking = newSteps > _steps;
      _steps = newSteps;
    });

    await _persistCurrentStepState();
    if (!mounted || _isDisposed) return;

    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(_steps);
    }

    WatchSyncService.instance.syncSteps(_steps, goal: _dailyGoal);

    if (_shouldSyncProgress()) {
      unawaited(_syncStepProgress());
    }

    if (_steps >= _dailyGoal) {
      unawaited(_saveDailyActivity(steps: true));
    }

    if (previousSteps < _dailyGoal && _steps >= _dailyGoal) {
      await _handleStepGoalCompleted();
    }

    if (_isWalking) {
      if (_lottieController.isAnimating == false && mounted) {
        _lottieController.repeat();
      }
    } else {
      if (mounted) {
        _lottieController.stop();
        _lottieController.animateTo(0,
            duration: const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _saveDailyActivity(
      {bool meditation = false, bool steps = false}) async {
    final userId = _currentUserId;
    if (userId == null) return;
    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      final userData = await _loadUserData();
      final username = userData['username']?.toString() ??
          userData['name']?.toString() ??
          userData['displayName']?.toString();

      await PendingStepSyncService.instance.flush(userId: userId);
      final response = await _dailyTrackerApiService.recordCompletedActivities(
        date: formattedDate,
        stepCount: _steps,
        stepGoal: _dailyGoal,
        meditation: meditation,
        steps: steps,
        username: username,
        companyId: userData['company_id']?.toString() ??
            userData['companyId']?.toString(),
        companyCode: userData['company_code']?.toString() ??
            userData['companyCode']?.toString(),
        companyName: userData['company_name']?.toString() ??
            userData['companyName']?.toString(),
      );
      _handleStepGoalAchievementResponse(response);
    } catch (error) {
      debugPrint('Failed to save daily step activity: $error');
      await PendingStepSyncService.instance.queueStepProgress(
        userId: userId,
        date: formattedDate,
        stepCount: _steps,
        stepGoal: _dailyGoal,
        steps: steps,
      );
    }
  }

  void _setWalkingState(bool isWalking) {
    if (!mounted || _isDisposed) return;

    if (_isWalking != isWalking) {
      setState(() {
        _isWalking = isWalking;
      });
    }

    if (isWalking) {
      _lottieController.forward(); // Start animation smoothly
    } else {
      _lottieController.stop();
      _lottieController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
      );
    }
  }

  bool _isUnrealisticStepJump(int newSteps, DateTime eventTime) {
    final delta = newSteps - _steps;
    if (delta <= 0) return false;

    final previousEventTime = _lastStepEventAt;
    if (previousEventTime == null) {
      return delta > _maxInitialStepJump;
    }

    final elapsedSeconds = math.max(
      eventTime.difference(previousEventTime).inMilliseconds / 1000,
      1.0,
    );
    final allowedDelta = math.max(
      _maxInstantStepJump,
      (elapsedSeconds * _maxStepsPerSecond).ceil() + 12,
    );

    return delta > allowedDelta;
  }

  void _handleRawStepCount(int rawSteps) {
    if (!mounted || _isDisposed) return;

    if (rawSteps <= _steps) {
      _lastRawStepCount = rawSteps;
      return;
    }

    final delta = rawSteps - _lastRawStepCount;
    _lastRawStepCount = rawSteps;

    if (delta <= 0) {
      return;
    }

    _updateStepCount(rawSteps);
  }

  Future<void> _syncStepProgress() async {
    final userId = _currentUserId;
    if (userId == null) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      await PendingStepSyncService.instance.flush(userId: userId);
      final response = await _dailyTrackerApiService.recordCompletedActivities(
        date: formattedDate,
        stepCount: _steps,
        stepGoal: _dailyGoal,
        steps: _steps > 0,
      );
      _handleStepGoalAchievementResponse(response);
      _lastSyncedStepCount = _steps;
    } catch (error) {
      debugPrint("Failed to sync step progress: $error");
      await PendingStepSyncService.instance.queueStepProgress(
        userId: userId,
        date: formattedDate,
        stepCount: _steps,
        stepGoal: _dailyGoal,
        steps: _steps > 0,
      );
    }
  }

  bool _shouldSyncProgress() {
    if (_lastSyncedStepCount == -1) return true;
    if (_steps == 0) return true;
    if (_steps >= _dailyGoal && _lastSyncedStepCount < _dailyGoal) return true;
    return (_steps - _lastSyncedStepCount).abs() >= 50;
  }

  String _formatSteps(int steps) {
    return NumberFormat.decimalPattern().format(steps);
  }

  String _todayKey() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<bool> _markStepGoalPromptIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _currentUserId ?? 'guest';
    final promptKey =
        'step_goal_memory_prompt_${userId}_${_todayKey()}_$_dailyGoal';

    if (prefs.getBool(promptKey) == true) {
      return false;
    }

    await prefs.setBool(promptKey, true);
    return true;
  }

  Future<void> _handleStepGoalCompleted() async {
    if (_stepGoalDialogVisible || !mounted || _isDisposed) return;

    final shouldShowPrompt = await _markStepGoalPromptIfNeeded();
    if (!shouldShowPrompt || !mounted || _isDisposed) return;

    await _showStepGoalCompleteDialog();
  }

  void _handleStepGoalAchievementResponse(Map<String, dynamic> response) {
    if (!mounted || _isDisposed) return;
    final rewards =
        DailyTrackerApiService.newStepGoalRewardsFromResponse(response);
    if (rewards.isNotEmpty) {
      _showStreakRewardSnackBar(rewards.last);
    }
  }

  void _showStreakRewardSnackBar(StepGoalReward reward) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Step medal unlocked: ${reward.title}'),
        action: SnackBarAction(
          label: 'View',
          onPressed: _openStepRewards,
        ),
      ),
    );
  }

  void _openStepRewards() {
    if (!mounted || _isDisposed) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationStreakRewardsScreen(
          activityType: ActivityStreakType.steps,
        ),
      ),
    );
  }

  Future<void> _showStepGoalCompleteDialog() async {
    if (_stepGoalDialogVisible || !mounted || _isDisposed) return;

    _stepGoalDialogVisible = true;
    final completedSteps = _steps;
    final formattedSteps = _formatSteps(completedSteps);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final dialogTheme = Theme.of(dialogContext);
        final isDark = dialogTheme.brightness == Brightness.dark;
        final surfaceColor =
            isDark ? dialogTheme.colorScheme.surface : const Color(0xFFFFFBF7);
        final borderColor = isDark
            ? dialogTheme.colorScheme.outlineVariant
            : const Color(0xFFE9DED5);
        final titleColor = dialogTheme.colorScheme.onSurface;
        final bodyColor = dialogTheme.colorScheme.onSurfaceVariant;
        final accentColor = dialogTheme.colorScheme.primary;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: borderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 28,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 74,
                  width: 74,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_walk_rounded,
                    color: accentColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Step goal complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You reached $formattedSteps steps today. Save this moment as a memory.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareStepMemory(completedSteps),
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Share with memories'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: dialogTheme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _stepGoalDialogVisible = false;
  }

  Future<ImageSource?> _showMemorySourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final sheetTheme = Theme.of(sheetContext);
        final titleColor = sheetTheme.colorScheme.onSurface;
        final accentColor = sheetTheme.colorScheme.primary;
        final handleColor = sheetTheme.colorScheme.outlineVariant;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_camera_rounded,
                    color: accentColor,
                  ),
                  title: Text(
                    'Take photo',
                    style: TextStyle(color: titleColor),
                  ),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_library_rounded,
                    color: accentColor,
                  ),
                  title: Text(
                    'Upload image',
                    style: TextStyle(color: titleColor),
                  ),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _shareStepMemory(int completedSteps) async {
    if (!mounted || _isDisposed) return;

    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || _isDisposed) return;

    final source = await _showMemorySourceSheet();
    if (source == null || !mounted || _isDisposed) return;

    XFile? image;
    try {
      image = await _memoryPicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
      );
    } catch (error) {
      debugPrint('Step memory picker failed: $error');
      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open image picker.')),
      );
      return;
    }

    if (image == null || !mounted || _isDisposed) return;

    final formattedSteps = _formatSteps(completedSteps);
    final memoryNote = Note(
      id: '',
      userId: '',
      username: '',
      title: 'Step Goal Memory',
      note: [
        {
          'type': 'text',
          'value':
              'I completed my daily step goal with $formattedSteps steps today.',
        },
      ],
      createdAt: DateTime.now(),
      category: 'Add Value',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesType(
          note: memoryNote,
          initialImage: image,
          initialCategory: 'Add Value',
          openCommunityAfterPost: true,
        ),
      ),
    );
  }

  Future<void> _openGoalScreen() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => StepGoalScreen(initialGoal: _dailyGoal),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _dailyGoal = result;
      });
      await _syncStepProgress();
    }
  }

  Future<void> _resumeStepCounterIfNeeded() async {
    if (!mounted) return;

    if (Platform.isIOS && !widget.debugAutoGrantStepPermission) {
      await _requestAppleHealthAccessForSession();
      await _loadSteps();
      if (!mounted || _isDisposed) return;
      setState(() {
        _stepCounterInitialized = true;
      });
      _dismissAppleHealthAccessDialogIfReady();
      if (!mounted || _isDisposed) return;
      await _startIosLiveStepCounter();
      await _showAppleHealthAccessDialogIfNeeded();
      return;
    }

    if (widget.debugAutoGrantStepPermission) {
      setState(() {
        _hasStepPermission = true;
        _stepPermissionMessage = null;
      });
      if (_stepCounterInitialized) {
        if (!widget.debugSkipBackgroundService) {
          unawaited(StepBackgroundService.instance.startTracking());
        }
        await _loadSteps();
        if (_checkTimer == null) {
          _startStepWatchdogTimer();
        }
        if (_statePersistTimer == null) {
          _startStepStateAutosave();
        }
        return;
      }
      _initStepCounter();
      return;
    }

    final status = await _stepPermission.status;
    if (!mounted || !status.isGranted) return;

    setState(() {
      _hasStepPermission = true;
      _stepPermissionMessage = null;
    });

    if (_stepCounterInitialized) {
      unawaited(StepBackgroundService.instance.startTracking());
      await _loadSteps();
      if (_checkTimer == null) {
        _startStepWatchdogTimer();
      }
      if (_statePersistTimer == null) {
        _startStepStateAutosave();
      }
      return;
    }

    _initStepCounter();
  }

  Future<void> _enableStepCounter() async {
    if (Platform.isIOS && !widget.debugAutoGrantStepPermission) {
      await _syncAppleHealthSteps(showFeedback: true);
      await _startIosLiveStepCounter();
      return;
    }

    if (_stepCounterInitialized) return;

    final hasPermission = await _requestPermission();
    if (!mounted || !hasPermission) return;

    _initStepCounter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startAppleHealthRefreshTimer();
        unawaited(_resumeStepCounterIfNeeded());
        break;
      case AppLifecycleState.paused:
        _stopAppleHealthRefreshTimer();
        unawaited(_persistCurrentStepState());
        unawaited(_pauseStepCounterForLifecycle());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _stopAppleHealthRefreshTimer();
        unawaited(_persistCurrentStepState());
        unawaited(_pauseStepCounterForLifecycle());
        break;
      case AppLifecycleState.detached:
        _stopAppleHealthRefreshTimer();
        unawaited(_persistCurrentStepState());
        unawaited(_stopStepCounterForLifecycle());
        break;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_persistCurrentStepState());
    _backgroundStepUpdates?.cancel();
    _stepCountStream?.cancel();
    _checkTimer?.cancel();
    _statePersistTimer?.cancel();
    _stopAppleHealthRefreshTimer();
    _stepStreamController.close();
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress =
        _dailyGoal <= 0 ? 0 : (_steps / _dailyGoal).clamp(0, 1).toDouble();
    final animationSize =
        context.isTabletWidth ? 360.0 : context.screenWidth * 0.7;

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final goalPanelColor = companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : const Color(0xFFFCF5EA);
              final infoPanelColor = companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : const Color(0xFFEAF6F4);
              final subtleTextColor = companyTheme.mutedInkColor;

              return Scaffold(
                backgroundColor: companyTheme.backgroundColor,
                body: SafeArea(
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          vertical: context.responsiveValue(20),
                        ),
                        child: ResponsiveContent(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Lottie.asset(
                                'assets/images/walking.json',
                                width: animationSize.clamp(220, 360),
                                height: animationSize.clamp(220, 360),
                                controller: _lottieController,
                                repeat: false,
                                onLoaded: (composition) {
                                  _lottieController.duration =
                                      composition.duration;
                                  _lottieController.value = 0;
                                },
                              ),
                              SizedBox(height: context.responsiveValue(10)),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Text(
                                    'Today ',
                                    style: TextStyle(
                                      fontSize: context.responsiveFont(15),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('(MMM dd, yyyy)')
                                        .format(DateTime.now()),
                                    style: TextStyle(
                                      fontSize: context.responsiveFont(15),
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: context.responsiveValue(10)),
                              StreamBuilder<int>(
                                stream: _stepStreamController.stream,
                                initialData: _steps,
                                builder: (context, snapshot) {
                                  return ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      colors: [
                                        Color(0xFF8bc074),
                                        Color(0xFFce8f5a)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ).createShader(bounds),
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.end,
                                      spacing: 5,
                                      children: [
                                        Text(
                                          '${snapshot.data ?? 0}',
                                          style: TextStyle(
                                            fontSize: context.responsiveFont(60,
                                                min: 0.8, max: 1.15),
                                            fontFamily: 'ralemed',
                                            color: Colors.white,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: context.responsiveValue(8),
                                          ),
                                          child: Text(
                                            'steps',
                                            style: TextStyle(
                                              fontSize:
                                                  context.responsiveFont(22),
                                              fontFamily: 'ralemed',
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: context.responsiveValue(10)),
                              if (Platform.isIOS &&
                                  !widget.debugAutoGrantStepPermission &&
                                  !_hasRecentIosLiveMovement()) ...[
                                TextButton.icon(
                                  onPressed: _isAppleHealthSyncing
                                      ? null
                                      : () => unawaited(
                                            _syncAppleHealthSteps(
                                              showFeedback: true,
                                            ),
                                          ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: companyTheme.iconColor,
                                  ),
                                  icon: _isAppleHealthSyncing
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              companyTheme.iconColor,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    'Sync Apple Health Steps',
                                    style: TextStyle(
                                      fontSize: context.responsiveFont(14),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(height: context.responsiveValue(10)),
                              ],
                              if (!_stepCounterInitialized ||
                                  _stepPermissionMessage != null)
                                Container(
                                  width: double.infinity,
                                  margin: EdgeInsets.symmetric(
                                    horizontal: context.isTabletWidth ? 20 : 0,
                                  ),
                                  padding: EdgeInsets.all(
                                      context.responsiveValue(14)),
                                  decoration: BoxDecoration(
                                    color: infoPanelColor,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _stepPermissionMessage ??
                                            'Enable live step tracking to update this count automatically.',
                                        style: TextStyle(
                                          fontSize: context.responsiveFont(14),
                                          color: companyTheme.inkColor,
                                          height: 1.35,
                                        ),
                                      ),
                                      if (!_hasStepPermission &&
                                          (!_stepCounterInitialized ||
                                              Platform.isIOS)) ...[
                                        SizedBox(
                                            height:
                                                context.responsiveValue(10)),
                                        TextButton.icon(
                                          onPressed: _isAppleHealthSyncing
                                              ? null
                                              : _enableStepCounter,
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                companyTheme.iconColor,
                                          ),
                                          icon:
                                              const Icon(Icons.directions_walk),
                                          label: Text(
                                            Platform.isIOS
                                                ? 'Sync Apple Health Steps'
                                                : 'Enable Step Tracking',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (!_stepCounterInitialized ||
                                  _stepPermissionMessage != null)
                                SizedBox(height: context.responsiveValue(10)),
                              Container(
                                width: double.infinity,
                                margin: EdgeInsets.symmetric(
                                  horizontal: context.isTabletWidth ? 20 : 0,
                                ),
                                padding:
                                    EdgeInsets.all(context.responsiveValue(18)),
                                decoration: BoxDecoration(
                                  color: goalPanelColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: companyTheme.iconColor
                                        .withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.flag_rounded,
                                          color: Color(0xFFCE8F5A),
                                        ),
                                        SizedBox(
                                            width: context.responsiveValue(10)),
                                        Expanded(
                                          child: Text(
                                            'Daily Goal: $_dailyGoal steps',
                                            style: TextStyle(
                                              fontSize:
                                                  context.responsiveFont(17),
                                              fontWeight: FontWeight.bold,
                                              color: companyTheme.inkColor,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _openGoalScreen,
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                companyTheme.iconColor,
                                          ),
                                          child: const Text(
                                            'Set Goal',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                        height: context.responsiveValue(8)),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: LinearProgressIndicator(
                                        minHeight: 10,
                                        value: progress,
                                        backgroundColor: theme
                                            .colorScheme.onSurface
                                            .withValues(alpha: 0.10),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          companyTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                        height: context.responsiveValue(10)),
                                    Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      runSpacing: 8,
                                      spacing: 16,
                                      children: [
                                        Text(
                                          '$_steps / $_dailyGoal',
                                          style:
                                              TextStyle(color: subtleTextColor),
                                        ),
                                        Text(
                                          '${(progress * 100).round()}% complete',
                                          style:
                                              TextStyle(color: subtleTextColor),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: context.responsiveValue(16)),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const TrackingScreen(title: ''),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFce8f5a),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: context.responsiveValue(20),
                                        vertical: context.responsiveValue(12),
                                      ),
                                    ),
                                    child: Text(
                                      'View Steps',
                                      style: GoogleFonts.roboto(
                                        color: Colors.white,
                                        fontSize: context.responsiveFont(16),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const StepMapTrackerScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('Track on Map'),
                                  ),
                                  if (_hasCoach)
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const StepSubmissionScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                      ),
                                      label: const Text('Submit Steps'),
                                    ),
                                ],
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const MyStepSubmissionsScreen(),
                                    ),
                                  );
                                },
                                child: const Text('View my submissions'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 10,
                        child: IconButton(
                          onPressed: _openStepRewards,
                          icon: const Icon(Icons.workspace_premium_rounded),
                          tooltip: 'Rewards',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

typedef StepTrackerState = _StepTrackerState;
