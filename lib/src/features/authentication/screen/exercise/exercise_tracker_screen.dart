import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_gallery_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/pending_exercise_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExerciseTrackerScreen extends StatefulWidget {
  const ExerciseTrackerScreen({super.key});

  @override
  State<ExerciseTrackerScreen> createState() => _ExerciseTrackerScreenState();
}

class _ExerciseTrackerScreenState extends State<ExerciseTrackerScreen> {
  static const List<String> _exerciseTypes = [
    'Pilates',
    'Exercise',
    'Gym',
    'Strength',
    'Yoga',
    'Cycling',
    'Swimming',
    'Dance',
    'HIIT',
    'Stretching',
    'Sports',
    'Other',
  ];

  static const String _sessionStartKey = 'exercise_session_start_ms';
  static const String _sessionGoalSecondsKey = 'exercise_session_goal_seconds';
  static const String _sessionGoalKey = 'exercise_session_goal_minutes';
  static const String _sessionTypeKey = 'exercise_session_type';
  static const String _sessionCustomTypeKey = 'exercise_session_custom_type';
  static const String _sessionIntensityKey = 'exercise_session_intensity';
  static const String _sessionNotesKey = 'exercise_session_notes';
  static const String _sessionStartPhotoKey = 'exercise_session_start_photo';
  static const String _sessionEndPhotoKey = 'exercise_session_end_photo';
  static const String _sessionStoppedDurationKey =
      'exercise_session_stopped_duration_seconds';
  static const String _sessionOwnerKey = 'exercise_session_owner_uid';
  static final List<int> _durationHourOptions =
      List<int>.generate(24, (index) => index);
  static final List<int> _durationMinuteSecondOptions =
      List<int>.generate(60, (index) => index);

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _customTypeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ExerciseApiService _exerciseApi = ExerciseApiService.instance;
  final FastingNotificationService _notificationService =
      FastingNotificationService.instance;
  final PendingExerciseSyncService _pendingExerciseSync =
      PendingExerciseSyncService.instance;

  String _selectedType = _exerciseTypes.first;
  ExerciseDurationSelection _goalDurationSelection =
      const ExerciseDurationSelection(hours: 0, minutes: 5, seconds: 0);
  int _intensity = 2;
  DateTime? _sessionStartAt;
  DateTime? _sessionEndsAt;
  Duration? _stoppedElapsedDuration;
  DateTime? _stoppedAt;
  String? _startPhotoUrl;
  String? _pendingEndPhotoUrl;
  bool _isUploadingEndPhoto = false;
  bool _isStarting = false;
  bool _isSaving = false;
  bool _isLoadingLogs = true;
  bool _isRestoringSession = true;
  bool _hasAnnouncedGoalReached = false;
  String? _saveRecoveryError;
  String? _clientSessionId;
  ExerciseSyncStatus _syncStatus = const ExerciseSyncStatus.idle();
  Timer? _sessionTimer;
  Timer? _completionAlarmTimer;
  final AudioPlayer _alarmPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  bool _alarmAudioContextConfigured = false;
  List<Map<String, dynamic>> _todayLogs = [];

  @override
  void dispose() {
    _pendingExerciseSync.status.removeListener(_onExerciseSyncStatusChanged);
    _sessionTimer?.cancel();
    _completionAlarmTimer?.cancel();
    // dispose() stops playback itself; no need to await the separate
    // stop() call _stopCompletionAlarm() would otherwise race against.
    _alarmPlayer.dispose();
    _customTypeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTodayLogs();
    _pendingExerciseSync.status.addListener(_onExerciseSyncStatusChanged);
    unawaited(_restoreAndRecoverExerciseSession());
  }

  Future<void> _restoreAndRecoverExerciseSession() async {
    await _restoreActiveSession();
    await _recoverLostExerciseCameraData();
    final userId = AuthService.instance.currentUserId;
    if (userId != null && userId.isNotEmpty) {
      await _pendingExerciseSync.refreshStatus(userId);
    }
  }

  void _onExerciseSyncStatusChanged() {
    final nextStatus = _pendingExerciseSync.status.value;
    final userId = AuthService.instance.currentUserId;
    if (!mounted || userId == null || nextStatus.userId != userId) return;
    setState(() => _syncStatus = nextStatus);
    if (nextStatus.phase == ExerciseSyncPhase.synced) {
      unawaited(_loadTodayLogs());
    }
  }

  Future<void> _loadTodayLogs() async {
    try {
      final logs = await _exerciseApi.fetchToday();
      if (!mounted) return;
      setState(() {
        _todayLogs = logs;
      });
    } catch (error) {
      debugPrint('Failed to load exercise logs: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLogs = false;
        });
      }
    }
  }

  bool get _isSessionActive =>
      _sessionStartAt != null && _sessionEndsAt != null;

  Duration _elapsedSessionTime() {
    final stoppedDuration = _stoppedElapsedDuration;
    if (stoppedDuration != null) return stoppedDuration;
    if (_sessionStartAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_sessionStartAt!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration _remainingSessionTime() {
    if (_stoppedElapsedDuration != null) return Duration.zero;
    if (_sessionEndsAt == null) return Duration.zero;
    final remaining = _sessionEndsAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get _selectedGoalDuration {
    return exerciseDurationFromSelection(_goalDurationSelection);
  }

  double _sessionProgress() {
    if (!_isSessionActive) return 0;
    final total = _sessionEndsAt!.difference(_sessionStartAt!).inSeconds;
    if (total <= 0) return 0;
    final elapsed = _elapsedSessionTime().inSeconds.clamp(0, total);
    return elapsed / total;
  }

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<void> _restoreActiveSession() async {
    try {
      final session = AuthService.instance.currentSession;
      if (session == null) return;
      final userId = session.id.toString();
      final localSession = await _pendingExerciseSync.loadActiveSession(userId);
      if (localSession != null) {
        await _hydrateLocalSession(localSession);
        return;
      }

      // Migration fallback for an active workout saved by the prior
      // remote-first tracker. New sessions are only written through the v2
      // local queue service above.
      final prefs = await _prefs;
      final startMs = prefs.getInt(_sessionStartKey);
      if (startMs == null) return;

      final ownerId = prefs.getString(_sessionOwnerKey);
      if (ownerId != null && ownerId != session.id.toString()) {
        await _clearActiveSessionCache(prefs);
        return;
      }

      final now = DateTime.now();
      final rawStart = DateTime.fromMillisecondsSinceEpoch(startMs);
      final start = rawStart.isAfter(now) ? now : rawStart;
      final totalSeconds = prefs.getInt(_sessionGoalSecondsKey) ??
          Duration(minutes: prefs.getInt(_sessionGoalKey) ?? 5).inSeconds;
      final goalDuration = normalizedExerciseSessionGoalDuration(
        Duration(seconds: totalSeconds),
      );
      final end = start.add(goalDuration);
      final stoppedSeconds = prefs.getInt(_sessionStoppedDurationKey);
      final stoppedDuration = stoppedSeconds == null
          ? null
          : boundedExerciseLogDuration(Duration(seconds: stoppedSeconds));
      final storedType = prefs.getString(_sessionTypeKey)?.trim();
      final storedCustomType =
          prefs.getString(_sessionCustomTypeKey)?.trim() ?? '';
      final usesKnownType =
          storedType != null && _exerciseTypes.contains(storedType);
      final selectedType = usesKnownType ? storedType : 'Other';
      final customType = usesKnownType
          ? storedCustomType
          : (storedCustomType.isNotEmpty
              ? storedCustomType
              : (storedType?.isNotEmpty == true ? storedType! : ''));
      final storedIntensity = prefs.getInt(_sessionIntensityKey);
      final intensity = storedIntensity != null &&
              storedIntensity >= 1 &&
              storedIntensity <= 3
          ? storedIntensity
          : 2;

      if (!mounted) return;
      setState(() {
        _sessionStartAt = start;
        _sessionEndsAt = end;
        _stoppedElapsedDuration = stoppedDuration;
        _stoppedAt =
            stoppedDuration == null ? null : start.add(stoppedDuration);
        _goalDurationSelection =
            exerciseDurationSelectionFromDuration(goalDuration);
        _selectedType = selectedType;
        _customTypeController.text = customType;
        _intensity = intensity;
        _notesController.text = prefs.getString(_sessionNotesKey) ?? '';
        _startPhotoUrl = prefs.getString(_sessionStartPhotoKey);
        _pendingEndPhotoUrl = prefs.getString(_sessionEndPhotoKey);
        _clientSessionId = _legacyClientSessionId(session.id.toString(), start);
        // A restored expired workout should be recoverable without suddenly
        // starting a looping alarm while the member is trying to stop it.
        _hasAnnouncedGoalReached = stoppedDuration != null || !end.isAfter(now);
        _saveRecoveryError = null;
      });

      if (stoppedDuration == null && _remainingSessionTime() > Duration.zero) {
        _startSessionTicker();
        await _syncExerciseNotification();
      } else {
        await _clearExerciseNotification();
      }

      // Repair malformed legacy cache so later app starts get the same safe
      // picker-compatible data rather than rebuilding an invalid dropdown.
      if (ownerId == null ||
          rawStart != start ||
          totalSeconds != goalDuration.inSeconds ||
          (stoppedSeconds != null &&
              stoppedSeconds != stoppedDuration!.inSeconds)) {
        await _persistActiveSession();
      }
    } catch (error) {
      debugPrint('Failed to restore exercise session: $error');
      try {
        await _clearActiveSessionCache();
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isRestoringSession = false);
      }
    }
  }

  Future<void> _hydrateLocalSession(ExerciseLocalSession local) async {
    final now = DateTime.now();
    final rawStart = local.startedAt;
    final start = rawStart.isAfter(now) ? now : rawStart;
    final goalDuration = normalizedExerciseSessionGoalDuration(
      Duration(seconds: local.goalDurationSeconds),
    );
    final end = start.add(goalDuration);
    final stoppedDuration = local.stoppedDurationSeconds == null
        ? null
        : boundedExerciseLogDuration(
            Duration(seconds: local.stoppedDurationSeconds!),
          );
    final usesKnownType = _exerciseTypes.contains(local.type);
    if (!mounted) return;
    setState(() {
      _clientSessionId = local.clientSessionId;
      _sessionStartAt = start;
      _sessionEndsAt = end;
      _stoppedElapsedDuration = stoppedDuration;
      _stoppedAt = local.stoppedAt ??
          (stoppedDuration == null ? null : start.add(stoppedDuration));
      _goalDurationSelection =
          exerciseDurationSelectionFromDuration(goalDuration);
      _selectedType = usesKnownType ? local.type : 'Other';
      _customTypeController.text = usesKnownType ? '' : local.type;
      _intensity = local.intensity.clamp(1, 3).toInt();
      _notesController.text = local.notes;
      _startPhotoUrl = local.startPhotoReference;
      _pendingEndPhotoUrl = local.pendingEndPhotoReference;
      _hasAnnouncedGoalReached = stoppedDuration != null || !end.isAfter(now);
      _saveRecoveryError = null;
    });
    if (stoppedDuration == null && _remainingSessionTime() > Duration.zero) {
      _startSessionTicker();
      unawaited(_syncExerciseNotification());
    } else {
      unawaited(_clearExerciseNotification());
    }
  }

  Future<void> _persistActiveSession() async {
    if (!_isSessionActive) return;
    final userId = AuthService.instance.currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Exercise session requires a signed-in user.');
    }
    final clientSessionId = _clientSessionId;
    if (clientSessionId == null || clientSessionId.isEmpty) {
      throw StateError('Exercise session is missing its local client ID.');
    }
    await _pendingExerciseSync.saveActiveSession(
      ExerciseLocalSession(
        clientSessionId: clientSessionId,
        userId: userId,
        type: _effectiveType(),
        goalDurationSeconds: _selectedGoalDuration.inSeconds,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startedAt: _sessionStartAt!,
        startPhotoReference: _startPhotoUrl,
        stoppedDurationSeconds: _stoppedElapsedDuration == null
            ? null
            : boundedExerciseLogDuration(_stoppedElapsedDuration!).inSeconds,
        stoppedAt: _stoppedAt,
        pendingEndPhotoReference: _pendingEndPhotoUrl,
      ),
    );
  }

  Future<void> _clearActiveSessionCache(
      [SharedPreferences? cachedPrefs]) async {
    final prefs = cachedPrefs ?? await _prefs;
    final userId = AuthService.instance.currentUserId;
    if (userId != null && userId.isNotEmpty) {
      await _pendingExerciseSync.clearActiveSession(userId: userId);
      await _pendingExerciseSync.clearCaptureIntent(userId: userId);
    }
    await prefs.remove(_sessionStartKey);
    await prefs.remove(_sessionGoalSecondsKey);
    await prefs.remove(_sessionGoalKey);
    await prefs.remove(_sessionTypeKey);
    await prefs.remove(_sessionCustomTypeKey);
    await prefs.remove(_sessionIntensityKey);
    await prefs.remove(_sessionNotesKey);
    await prefs.remove(_sessionStartPhotoKey);
    await prefs.remove(_sessionEndPhotoKey);
    await prefs.remove(_sessionStoppedDurationKey);
    await prefs.remove(_sessionOwnerKey);
  }

  String _legacyClientSessionId(String userId, DateTime start) =>
      'legacy_${userId}_${start.millisecondsSinceEpoch}';

  String _newClientSessionId() =>
      'exercise_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  void _stopSessionTicker() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  void _startSessionTicker() {
    _stopSessionTicker();
    if (!_isSessionActive) return;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isSessionActive) {
        _stopSessionTicker();
        return;
      }
      final remaining = _remainingSessionTime();
      if (remaining == Duration.zero && !_hasAnnouncedGoalReached) {
        _hasAnnouncedGoalReached = true;
        _playCompletionAlarm();
        _showMessage('Exercise goal reached. Great work!');
      }
      setState(() {});
      if (remaining == Duration.zero) {
        _stopSessionTicker();
      }
    });
  }

  Future<void> _ensureAlarmAudioContext() async {
    if (_alarmAudioContextConfigured) return;
    try {
      await _alarmPlayer.setAudioContext(
        AudioContext(
          // .playback (rather than .ambient) is what makes iOS keep
          // playing -- and audibly ring -- even when the ring/silent
          // switch is flipped to silent, the same way a real alarm clock
          // does.
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
      _alarmAudioContextConfigured = true;
    } catch (error) {
      debugPrint('Failed to configure exercise alarm audio context: $error');
    }
  }

  // Loops an actual alarm sound file until the workout is stopped and
  // saved. This used to call SystemSound.play(SystemSoundType.alert) on a
  // repeating timer, but that API is a short one-shot UI click meant for
  // things like picker feedback -- both iOS and Android throttle/ignore
  // repeated calls to it in quick succession, so only the very first tick
  // was ever actually audible and everything after it was silently
  // dropped, which is why it sounded like "a single tone" instead of a
  // continuing alarm. Looping a real audio asset (the same sleep_alarm
  // sound already used for the sleep tracker's alarm) has no such
  // throttling and keeps ringing for as long as the timer below is alive.
  Future<void> _playCompletionAlarm() async {
    _completionAlarmTimer?.cancel();
    HapticFeedback.heavyImpact();

    try {
      await _ensureAlarmAudioContext();
      await _alarmPlayer.stop();
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(AssetSource('audio/sleep_alarm.wav'));
    } catch (error) {
      debugPrint('Failed to play exercise completion alarm: $error');
    }

    _completionAlarmTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => HapticFeedback.heavyImpact(),
    );
  }

  Future<void> _stopCompletionAlarm() async {
    _completionAlarmTimer?.cancel();
    _completionAlarmTimer = null;
    try {
      await _alarmPlayer.stop();
    } catch (error) {
      debugPrint('Failed to stop exercise completion alarm: $error');
    }
  }

  Future<bool> _syncExerciseNotification() async {
    if (_sessionEndsAt == null) return false;

    try {
      await _notificationService.ensurePermissions();
      await _notificationService.scheduleExerciseCompleteNotification(
        endsAt: _sessionEndsAt!,
        goalDuration: _selectedGoalDuration,
      );
      return true;
    } catch (error) {
      debugPrint('Failed to schedule exercise completion alert: $error');
      return false;
    }
  }

  Future<void> _clearExerciseNotification() async {
    try {
      await _notificationService.cancelExerciseCompleteNotification();
    } catch (error) {
      debugPrint('Failed to clear exercise completion alert: $error');
    }
  }

  String _effectiveType() {
    final custom = _customTypeController.text.trim();
    // Keep legacy in-progress sessions recoverable. Older versions allowed
    // an empty custom value and stored the literal "Other"; a new workout
    // still validates that case before it can start.
    if (_selectedType == 'Other') return custom.isEmpty ? 'Other' : custom;
    return _selectedType;
  }

  /// Opens the native camera only after recording enough intent to recover an
  /// Android process kill via `retrieveLostData`. The returned value is an
  /// opaque local reference; it is intentionally never uploaded here.
  Future<String?> _captureExercisePhotoLocally(
    ExerciseCaptureIntent intent,
  ) async {
    await _pendingExerciseSync.saveCaptureIntent(intent);
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1800,
      );
      if (pickedImage == null) {
        await _pendingExerciseSync.clearCaptureIntent(userId: intent.userId);
        return null;
      }
      final bytes = await pickedImage.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('The camera did not return a usable photo.');
      }
      final reference = await _pendingExerciseSync.persistPhoto(
        userId: intent.userId,
        clientSessionId: intent.clientSessionId,
        slot: intent.slot,
        bytes: bytes,
      );
      await _pendingExerciseSync.clearCaptureIntent(userId: intent.userId);
      return reference;
    } catch (error) {
      debugPrint('Could not capture exercise photo locally: $error');
      rethrow;
    }
  }

  Future<void> _recoverLostExerciseCameraData() async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null || userId.isEmpty) return;
    final intent = await _pendingExerciseSync.loadCaptureIntent(userId);
    if (intent == null) return;
    try {
      final lost = await _imagePicker.retrieveLostData();
      final image = lost.file;
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return;
      final reference = await _pendingExerciseSync.persistPhoto(
        userId: intent.userId,
        clientSessionId: intent.clientSessionId,
        slot: intent.slot,
        bytes: bytes,
      );
      await _pendingExerciseSync.clearCaptureIntent(userId: intent.userId);
      if (intent.slot == ExerciseCaptureSlot.start) {
        if (!mounted || _isSessionActive) return;
        final startedAt = DateTime.now();
        if (mounted) {
          setState(() {
            _clientSessionId = intent.clientSessionId;
            _selectedType =
                _exerciseTypes.contains(intent.type) ? intent.type : 'Other';
            _customTypeController.text =
                _exerciseTypes.contains(intent.type) ? '' : intent.type;
            _goalDurationSelection = exerciseDurationSelectionFromDuration(
              normalizedExerciseSessionGoalDuration(
                Duration(seconds: intent.goalDurationSeconds),
              ),
            );
            _intensity = intent.intensity.clamp(1, 3).toInt();
            _notesController.text = intent.notes;
            _startPhotoUrl = reference;
            _sessionStartAt = startedAt;
            _sessionEndsAt = startedAt.add(_selectedGoalDuration);
            _stoppedElapsedDuration = null;
            _hasAnnouncedGoalReached = false;
          });
        }
        await _persistActiveSession();
        _startSessionTicker();
        unawaited(_syncStartedExerciseNotification(startedAt));
        if (mounted) {
          _showMessage('Recovered your start photo. Exercise is running.');
        }
        return;
      }

      final active = await _pendingExerciseSync.loadActiveSession(userId);
      final startedAt = intent.startedAt ?? active?.startedAt;
      final endedAt = intent.endedAt;
      if (startedAt == null || endedAt == null) return;
      final duration =
          boundedExerciseLogDuration(endedAt.difference(startedAt));
      final record = PendingExerciseRecord(
        clientSessionId: intent.clientSessionId,
        userId: userId,
        type: intent.type,
        durationSeconds: duration.inSeconds,
        intensity: intent.intensity,
        notes: intent.notes,
        startedAt: startedAt,
        endedAt: endedAt,
        startPhotoReference:
            intent.startPhotoReference ?? active?.startPhotoReference,
        endPhotoReference: reference,
      );
      await _pendingExerciseSync.queueCompleted(record);
      await _pendingExerciseSync.clearActiveSession(userId: userId);
      if (mounted) {
        _resetCompletedSessionState();
        _showMessage('Recovered your end photo — saved on this device.');
      }
      unawaited(_pendingExerciseSync.flush(userId: userId));
    } catch (error) {
      debugPrint('Could not recover an exercise camera photo: $error');
    }
  }

  bool _matchesActiveSession(DateTime startedAt) =>
      _sessionStartAt?.isAtSameMomentAs(startedAt) ?? false;

  Future<void> _syncStartedExerciseNotification(DateTime startedAt) async {
    final notificationsReady = await _syncExerciseNotification();
    if (!mounted || !_matchesActiveSession(startedAt) || notificationsReady) {
      return;
    }
    _showMessage(
        'Exercise is running, but completion alerts are unavailable right now.');
  }

  Future<void> _startExerciseSession() async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSaving || _isStarting || _isSessionActive) return;

    final customType = _customTypeController.text.trim();
    if (_selectedType == 'Other' && customType.isEmpty) {
      _showMessage('Enter an exercise type.');
      return;
    }
    if (_selectedGoalDuration <= Duration.zero) {
      _showMessage('Pick an exercise duration first.');
      return;
    }

    final userId = session.id.toString();
    final clientSessionId = _newClientSessionId();
    final goalDuration = _selectedGoalDuration;
    final type = _effectiveType();
    try {
      unawaited(_stopCompletionAlarm());
      setState(() => _isStarting = true);
      final startPhotoReference = await _captureExercisePhotoLocally(
        ExerciseCaptureIntent(
          userId: userId,
          clientSessionId: clientSessionId,
          slot: ExerciseCaptureSlot.start,
          type: type,
          goalDurationSeconds: goalDuration.inSeconds,
          intensity: _intensity,
          notes: _notesController.text.trim(),
        ),
      );
      if (startPhotoReference == null) {
        if (mounted) {
          _showMessage('Start photo was not captured. Tap play to try again.');
        }
        return;
      }
      final startedAt = DateTime.now();
      final localSession = ExerciseLocalSession(
        clientSessionId: clientSessionId,
        userId: userId,
        type: type,
        goalDurationSeconds: goalDuration.inSeconds,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startedAt: startedAt,
        startPhotoReference: startPhotoReference,
      );
      // The start image and session must be durable before the timer begins.
      await _pendingExerciseSync.saveActiveSession(localSession);
      if (!mounted || AuthService.instance.currentUserId != userId) return;
      setState(() {
        _clientSessionId = clientSessionId;
        _sessionStartAt = startedAt;
        _sessionEndsAt = startedAt.add(goalDuration);
        _stoppedElapsedDuration = null;
        _stoppedAt = null;
        _startPhotoUrl = startPhotoReference;
        _pendingEndPhotoUrl = null;
        _hasAnnouncedGoalReached = false;
        _saveRecoveryError = null;
      });
      _startSessionTicker();
      unawaited(_syncStartedExerciseNotification(startedAt));
      _showMessage(
        'Exercise started. We will alert you when the '
        '${formatExerciseDuration(goalDuration)} goal is done.',
      );
    } catch (error) {
      debugPrint('Exercise start failed: $error');
      if (mounted) {
        _showMessage('Could not save the start photo. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _stopExerciseSession() async {
    final session = AuthService.instance.currentSession;
    if (session == null ||
        _isSaving ||
        _isUploadingEndPhoto ||
        !_isSessionActive) {
      return;
    }

    final type = _effectiveType();
    if (type.trim().isEmpty) {
      _showMessage('Enter an exercise type.');
      return;
    }

    final userId = session.id.toString();
    final originalStartedAt = _sessionStartAt!;
    final clientSessionId =
        _clientSessionId ?? _legacyClientSessionId(userId, originalStartedAt);
    final elapsedAtStop = _elapsedSessionTime();
    final logDuration = boundedExerciseLogDuration(elapsedAtStop);
    final durationWasCapped = exerciseLogDurationWasCapped(elapsedAtStop);
    final isFirstStopAttempt = _stoppedElapsedDuration == null;
    final endedAt = _stoppedAt ?? DateTime.now();

    // Freeze immediately while the member uses the native camera. No network
    // work happens in this path, so Stop remains responsive offline.
    unawaited(_stopCompletionAlarm());
    _stopSessionTicker();
    unawaited(_clearExerciseNotification());

    setState(() {
      if (isFirstStopAttempt) {
        _stoppedElapsedDuration = elapsedAtStop;
        _stoppedAt = endedAt;
      }
      _isUploadingEndPhoto = true;
      _saveRecoveryError = null;
    });
    try {
      final frozenDuration = isFirstStopAttempt
          ? logDuration
          : boundedExerciseLogDuration(_stoppedElapsedDuration!);
      final frozenEndedAt = _stoppedAt ?? endedAt;
      // Persist the frozen stop state before presenting the camera. If the
      // OS kills the app, restore/lost-data recovery retains this exact time.
      await _pendingExerciseSync.saveActiveSession(
        ExerciseLocalSession(
          clientSessionId: clientSessionId,
          userId: userId,
          type: type,
          goalDurationSeconds: _selectedGoalDuration.inSeconds,
          intensity: _intensity,
          notes: _notesController.text.trim(),
          startedAt: originalStartedAt,
          startPhotoReference: _startPhotoUrl,
          stoppedDurationSeconds: frozenDuration.inSeconds,
          stoppedAt: frozenEndedAt,
          pendingEndPhotoReference: _pendingEndPhotoUrl,
        ),
      );
      var endPhotoReference = _pendingEndPhotoUrl;
      if (endPhotoReference == null || endPhotoReference.isEmpty) {
        endPhotoReference = await _captureExercisePhotoLocally(
          ExerciseCaptureIntent(
            userId: userId,
            clientSessionId: clientSessionId,
            slot: ExerciseCaptureSlot.end,
            type: type,
            goalDurationSeconds: _selectedGoalDuration.inSeconds,
            intensity: _intensity,
            notes: _notesController.text.trim(),
            startedAt: originalStartedAt,
            endedAt: frozenEndedAt,
            startPhotoReference: _startPhotoUrl,
          ),
        );
      }
      if (endPhotoReference == null) {
        if (mounted) {
          _showMessage('End photo was not captured. Tap stop to try again.');
        }
        return;
      }
      if (!mounted || !_matchesActiveSession(originalStartedAt)) return;
      setState(() {
        _pendingEndPhotoUrl = endPhotoReference;
        _isUploadingEndPhoto = false;
        _isSaving = true;
      });
      // Attach the locally saved end image to the active session first, then
      // enqueue its immutable completed record. If the queue write fails, the
      // frozen session/photo remain available for a safe retry.
      await _pendingExerciseSync.saveActiveSession(
        ExerciseLocalSession(
          clientSessionId: clientSessionId,
          userId: userId,
          type: type,
          goalDurationSeconds: _selectedGoalDuration.inSeconds,
          intensity: _intensity,
          notes: _notesController.text.trim(),
          startedAt: originalStartedAt,
          startPhotoReference: _startPhotoUrl,
          stoppedDurationSeconds: frozenDuration.inSeconds,
          stoppedAt: frozenEndedAt,
          pendingEndPhotoReference: endPhotoReference,
        ),
      );
      final record = PendingExerciseRecord(
        clientSessionId: clientSessionId,
        userId: userId,
        type: type,
        durationSeconds: frozenDuration.inSeconds,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startedAt: originalStartedAt,
        endedAt: frozenEndedAt,
        startPhotoReference: _startPhotoUrl,
        endPhotoReference: endPhotoReference,
      );
      await _pendingExerciseSync.queueCompleted(record);
      await _pendingExerciseSync.clearActiveSession(userId: userId);
      if (!mounted) return;
      _resetCompletedSessionState();
      _showMessage(
        durationWasCapped
            ? 'Saved on this device at the 24-hour maximum — pending sync.'
            : 'Saved on this device — pending sync.',
      );
      unawaited(_pendingExerciseSync.flush(userId: userId));
    } catch (error) {
      debugPrint('Could not save exercise locally: $error');
      if (mounted) {
        final message = 'Could not save locally. Your stopped workout remains '
            'on this device; tap stop to retry.';
        setState(() => _saveRecoveryError = message);
        _showMessage(message);
      }
    } finally {
      if (mounted && _matchesActiveSession(originalStartedAt)) {
        setState(() {
          _isSaving = false;
          _isUploadingEndPhoto = false;
        });
      }
    }
  }

  void _resetCompletedSessionState() {
    if (!mounted) return;
    setState(() {
      _selectedType = _exerciseTypes.first;
      _goalDurationSelection =
          const ExerciseDurationSelection(hours: 0, minutes: 5, seconds: 0);
      _intensity = 2;
      _customTypeController.clear();
      _notesController.clear();
      _clientSessionId = null;
      _startPhotoUrl = null;
      _pendingEndPhotoUrl = null;
      _sessionStartAt = null;
      _sessionEndsAt = null;
      _stoppedElapsedDuration = null;
      _stoppedAt = null;
      _hasAnnouncedGoalReached = false;
      _saveRecoveryError = null;
      _isSaving = false;
      _isUploadingEndPhoto = false;
    });
  }

  // A deliberate recovery choice remains available for a mistaken workout,
  // a session the member no longer wants to save, or a transient save that
  // they prefer not to retry.
  Future<bool> _confirmDiscardSession() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this workout?'),
            content: const Text(
              "This clears the in-progress session without saving it. "
              "Use this if it's stuck (for example, left running for a "
              'very long time) or was started by mistake.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _discardActiveSession() async {
    if (_isSaving || !_isSessionActive) return;

    final confirmed = await _confirmDiscardSession();
    if (!confirmed || !mounted) return;

    unawaited(_stopCompletionAlarm());
    await _clearExerciseNotification();
    try {
      await _clearActiveSessionCache();
    } catch (error) {
      debugPrint('Could not clear discarded exercise session: $error');
    }
    _stopSessionTicker();

    if (!mounted) return;
    setState(() {
      _selectedType = _exerciseTypes.first;
      _goalDurationSelection =
          const ExerciseDurationSelection(hours: 0, minutes: 5, seconds: 0);
      _intensity = 2;
      _customTypeController.clear();
      _notesController.clear();
      _startPhotoUrl = null;
      _pendingEndPhotoUrl = null;
      _sessionStartAt = null;
      _sessionEndsAt = null;
      _stoppedElapsedDuration = null;
      _stoppedAt = null;
      _hasAnnouncedGoalReached = false;
      _isStarting = false;
      _isUploadingEndPhoto = false;
      _saveRecoveryError = null;
    });
    _showMessage('Workout discarded.');
  }

  Future<void> _deleteExercise(String logId) async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;

    try {
      await _exerciseApi.delete(logId);
      await _loadTodayLogs();
      if (!mounted) return;
      _showMessage('Exercise removed.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not remove exercise.');
      debugPrint('Exercise delete failed: $error');
    }
  }

  void _openExerciseRewards() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationStreakRewardsScreen(
          activityType: ActivityStreakType.exercise,
        ),
      ),
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;
    return CompanyThemeBuilder(
      builder: (context, theme) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            backgroundColor: theme.isDark ? theme.surfaceColor : Colors.white,
            foregroundColor: theme.isDark ? theme.inkColor : null,
            surfaceTintColor: Colors.transparent,
            title: const Text('Exercise'),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => const ExerciseGalleryScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: 'Exercise gallery',
              ),
              IconButton(
                onPressed: _openExerciseRewards,
                icon: const Icon(Icons.workspace_premium_rounded),
                tooltip: 'Rewards',
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: session == null
              ? Center(
                  child: Text(
                    'Sign in to log exercise.',
                    style: TextStyle(color: theme.inkColor),
                  ),
                )
              : _isRestoringSession
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      children: [
                        _buildSummary(theme, _todayLogs),
                        const SizedBox(height: 16),
                        _buildLogger(theme),
                        const SizedBox(height: 18),
                        _isLoadingLogs
                            ? const Center(child: CircularProgressIndicator())
                            : _buildTodayLogs(theme, _todayLogs),
                      ],
                    ),
        );
      },
    );
  }

  Widget _buildSummary(
    CompanyThemeData theme,
    List<Map<String, dynamic>> logs,
  ) {
    final totalMinutes = logs.fold<int>(
      0,
      (total, doc) => total + _readInt(doc['durationMinutes']),
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/exercise.gif',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.22),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.flame_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's exercise",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${logs.length} session${logs.length == 1 ? '' : 's'} - $totalMinutes min',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pilates, gym, yoga, sports, and custom exercise all count.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogger(CompanyThemeData theme) {
    final controlsDisabled = _isSaving || _isStarting || _isSessionActive;
    final primaryActionDisabled =
        _isSaving || _isStarting || _isUploadingEndPhoto;
    return _ThemedPanel(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log activity',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('exercise-type-$_selectedType'),
            initialValue: _selectedType,
            isExpanded: true,
            dropdownColor: theme.surfaceColor,
            decoration: _inputDecoration(
              theme,
              label: 'Activity type',
              hint: 'Choose the kind of exercise',
            ),
            items: _exerciseTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: controlsDisabled
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedType = value;
                      if (value != 'Other') {
                        _customTypeController.clear();
                      }
                    });
                  },
          ),
          if (_selectedType == 'Other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customTypeController,
              enabled: !controlsDisabled,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: theme.inkColor),
              decoration: _inputDecoration(
                theme,
                label: 'Exercise type',
                hint: 'Example: Boxing, barre, tennis',
              ),
            ),
          ],
          const SizedBox(height: 18),
          _buildDurationPicker(theme),
          const SizedBox(height: 16),
          _buildIntensityControl(theme, disabled: controlsDisabled),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            enabled: !controlsDisabled,
            maxLines: 3,
            style: TextStyle(color: theme.inkColor),
            decoration: _inputDecoration(
              theme,
              label: 'Notes',
              hint: 'What did you work on?',
            ),
          ),
          const SizedBox(height: 18),
          _buildSessionStatus(theme),
          if (_saveRecoveryError != null) ...[
            const SizedBox(height: 12),
            _buildSaveRecoveryNotice(theme),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: primaryActionDisabled
                  ? null
                  : _isSessionActive
                      ? _stopExerciseSession
                      : _startExerciseSession,
              icon: (_isStarting || _isSaving || _isUploadingEndPhoto)
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isSessionActive
                          ? CupertinoIcons.stop_circle_fill
                          : CupertinoIcons.play_circle_fill,
                    ),
              label: Text(
                _isStarting
                    ? 'Opening camera...'
                    : _isSaving
                        ? 'Saving locally...'
                        : _isUploadingEndPhoto
                            ? 'Opening camera...'
                            : _isSessionActive
                                ? (_saveRecoveryError != null
                                    ? 'Retry save'
                                    : 'Stop & save')
                                : 'Play exercise',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor:
                    theme.isDark ? theme.backgroundColor : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (_isSessionActive) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _isSaving ? null : _discardActiveSession,
                child: Text(
                  'Discard workout',
                  style: TextStyle(color: theme.mutedInkColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDurationPicker(CompanyThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controlLabel(theme, 'Goal duration'),
        const SizedBox(height: 8),
        Text(
          'Set hours, minutes, and seconds before you press play.',
          style: TextStyle(
            color: theme.mutedInkColor,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _durationDropdown(
                theme,
                label: 'Hours',
                value: _goalDurationSelection.hours,
                items: _durationHourOptions,
                onChanged: _isSessionActive || _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _goalDurationSelection =
                              _goalDurationSelection.copyWith(hours: value);
                        });
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _durationDropdown(
                theme,
                label: 'Minutes',
                value: _goalDurationSelection.minutes,
                items: _durationMinuteSecondOptions,
                onChanged: _isSessionActive || _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _goalDurationSelection =
                              _goalDurationSelection.copyWith(minutes: value);
                        });
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _durationDropdown(
                theme,
                label: 'Seconds',
                value: _goalDurationSelection.seconds,
                items: _durationMinuteSecondOptions,
                onChanged: _isSessionActive || _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _goalDurationSelection =
                              _goalDurationSelection.copyWith(seconds: value);
                        });
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Selected: ${formatExerciseDuration(_selectedGoalDuration)}',
          style: TextStyle(
            color: theme.inkColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _durationDropdown(
    CompanyThemeData theme, {
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?>? onChanged,
  }) {
    return DropdownButtonFormField<int>(
      key: ValueKey('exercise-duration-$label-$value'),
      initialValue: value,
      isExpanded: true,
      dropdownColor: theme.surfaceColor,
      decoration: _inputDecoration(
        theme,
        label: label,
        hint: label,
      ),
      items: items
          .map(
            (option) => DropdownMenuItem<int>(
              value: option,
              child: Text(option.toString().padLeft(2, '0')),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSaveRecoveryNotice(CompanyThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: theme.isDark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: theme.isDark ? 0.5 : 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.cloud_off_outlined, color: Colors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _saveRecoveryError!,
              style: TextStyle(
                color: theme.inkColor,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStatus(CompanyThemeData theme) {
    final active = _isSessionActive;
    final remaining = _remainingSessionTime();
    final elapsed = _elapsedSessionTime();
    final waitingToSave = _stoppedElapsedDuration != null;
    final durationWasCapped = exerciseLogDurationWasCapped(elapsed);
    final percent = (_sessionProgress() * 100).round().clamp(0, 100);
    final syncText = switch (_syncStatus.phase) {
      ExerciseSyncPhase.savingLocally => 'Saving on this device…',
      ExerciseSyncPhase.pendingSync => _syncStatus.error == null
          ? 'Saved on this device — pending sync.'
          : 'Saved on this device — sync will retry.',
      ExerciseSyncPhase.syncing => 'Syncing saved exercise…',
      ExerciseSyncPhase.synced => 'Exercise synced.',
      ExerciseSyncPhase.idle => null,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active
              ? theme.primaryColor.withValues(alpha: 0.2)
              : theme.mutedInkColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (active ? theme.primaryColor : theme.mutedInkColor)
                      .withValues(alpha: theme.isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  active ? CupertinoIcons.timer : CupertinoIcons.clock,
                  color: active ? theme.primaryColor : theme.mutedInkColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  active
                      ? (waitingToSave
                          ? 'Workout ready to save'
                          : 'Workout in progress')
                      : 'Ready to start',
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                active
                    ? '$percent%'
                    : formatExerciseDuration(_selectedGoalDuration),
                style: TextStyle(
                  color: theme.mutedInkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _sessionProgress().clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: theme.mutedInkColor.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              waitingToSave
                  ? 'Stopped at ${formatExerciseDuration(elapsed)}. '
                      'Retry save when ready.'
                  : 'Remaining ${formatExerciseDuration(remaining)}',
              style: TextStyle(
                color: theme.mutedInkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Elapsed ${formatExerciseDuration(elapsed)}',
              style: TextStyle(
                color: theme.mutedInkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (durationWasCapped) ...[
              const SizedBox(height: 10),
              Text(
                'This workout has been open for more than 24 hours. '
                'Stop & save will record the maximum valid duration '
                '(24 hours), or you can discard it.',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (_startPhotoUrl != null) ...[
              const SizedBox(height: 12),
              _LogPhotoPreview(
                theme: theme,
                label: 'Start photo',
                imageUrl: _startPhotoUrl!,
              ),
            ],
            if (_pendingEndPhotoUrl != null) ...[
              const SizedBox(height: 12),
              _LogPhotoPreview(
                theme: theme,
                label: 'End photo ready for retry',
                imageUrl: _pendingEndPhotoUrl!,
              ),
            ],
            if (_hasAnnouncedGoalReached) ...[
              const SizedBox(height: 10),
              Text(
                'Goal reached. Tap stop to capture your end photo and save.',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Tap play to capture your start photo and begin the timer.',
              style: TextStyle(
                color: theme.mutedInkColor,
                height: 1.35,
              ),
            ),
          ],
          if (syncText != null) ...[
            const SizedBox(height: 10),
            Text(
              syncText,
              style: TextStyle(
                color: _syncStatus.phase == ExerciseSyncPhase.pendingSync
                    ? theme.primaryColor
                    : theme.mutedInkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntensityControl(
    CompanyThemeData theme, {
    required bool disabled,
  }) {
    final labels = ['Easy', 'Moderate', 'Hard'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controlLabel(theme, 'Intensity'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          // No per-segment icon and no built-in selected checkmark: with
          // three equal-width segments, "Moderate" was the one long
          // enough that adding icon + checkmark width on top of its text
          // left too little room, so it wrapped mid-word ("Moderat" /
          // "e") instead of fitting on one line. The highlighted
          // background/foreground color already shows which one is
          // selected, so the icons were decorative, not load-bearing.
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < labels.length; i++)
              ButtonSegment<int>(
                value: i + 1,
                label: Text(
                  labels[i],
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: {_intensity},
          onSelectionChanged: disabled
              ? null
              : (values) => setState(() => _intensity = values.first),
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? theme.primaryColor
                  : theme.inkColor;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayLogs(
    CompanyThemeData theme,
    List<Map<String, dynamic>> logs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Logged today',
          style: TextStyle(
            color: theme.inkColor,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          _ThemedPanel(
            theme: theme,
            child: Text(
              'No exercise logged yet. Add pilates, gym, yoga, sports, or any custom movement.',
              style: TextStyle(color: theme.mutedInkColor, height: 1.4),
            ),
          )
        else
          ...logs.map((doc) {
            final data = doc;
            return _ExerciseLogTile(
              theme: theme,
              title: (data['type'] as String?)?.trim() ?? 'Exercise',
              minutes: _readInt(data['durationMinutes']),
              seconds: _readInt(data['durationSeconds']),
              intensity: _readInt(data['intensity']),
              notes: (data['notes'] as String?)?.trim() ?? '',
              startPhotoUrl: (data['startPhotoUrl'] as String?)?.trim(),
              endPhotoUrl: (data['endPhotoUrl'] as String?)?.trim(),
              onDelete: () => _deleteExercise((data['id'] as String?) ?? ''),
            );
          }),
      ],
    );
  }

  Widget _controlLabel(CompanyThemeData theme, String label) {
    return Text(
      label,
      style: TextStyle(
        color: theme.inkColor,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  InputDecoration _inputDecoration(
    CompanyThemeData theme, {
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: theme.mutedInkColor),
      hintStyle: TextStyle(color: theme.mutedInkColor.withValues(alpha: 0.7)),
      filled: true,
      fillColor: theme.isDark
          ? theme.backgroundColor.withValues(alpha: 0.72)
          : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: theme.mutedInkColor.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:
            BorderSide(color: theme.mutedInkColor.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
      ),
    );
  }
}

class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({
    required this.theme,
    required this.child,
  });

  final CompanyThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.isDark
              ? theme.primaryColor.withValues(alpha: 0.18)
              : theme.mutedInkColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.theme,
    required this.icon,
  });

  final CompanyThemeData theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: theme.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: theme.primaryColor),
    );
  }
}

class _ExerciseLogTile extends StatelessWidget {
  const _ExerciseLogTile({
    required this.theme,
    required this.title,
    required this.minutes,
    required this.seconds,
    required this.intensity,
    required this.notes,
    required this.startPhotoUrl,
    required this.endPhotoUrl,
    required this.onDelete,
  });

  final CompanyThemeData theme;
  final String title;
  final int minutes;
  final int seconds;
  final int intensity;
  final String notes;
  final String? startPhotoUrl;
  final String? endPhotoUrl;
  final VoidCallback onDelete;

  String get _intensityLabel {
    switch (intensity) {
      case 1:
        return 'Easy';
      case 3:
        return 'Hard';
      default:
        return 'Moderate';
    }
  }

  String get _durationLabel {
    final totalSeconds = seconds > 0 ? seconds : minutes * 60;
    return formatExerciseDuration(Duration(seconds: totalSeconds));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _ThemedPanel(
        theme: theme,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(theme: theme, icon: CupertinoIcons.checkmark_alt_circle),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_durationLabel - $_intensityLabel',
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      notes,
                      style: TextStyle(
                        color: theme.mutedInkColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if ((startPhotoUrl?.isNotEmpty ?? false) ||
                      (endPhotoUrl?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (startPhotoUrl?.isNotEmpty ?? false)
                          Expanded(
                            child: _LogPhotoPreview(
                              theme: theme,
                              label: 'Start',
                              imageUrl: startPhotoUrl!,
                            ),
                          ),
                        if ((startPhotoUrl?.isNotEmpty ?? false) &&
                            (endPhotoUrl?.isNotEmpty ?? false))
                          const SizedBox(width: 8),
                        if (endPhotoUrl?.isNotEmpty ?? false)
                          Expanded(
                            child: _LogPhotoPreview(
                              theme: theme,
                              label: 'End',
                              imageUrl: endPhotoUrl!,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove exercise',
              onPressed: onDelete,
              icon: Icon(CupertinoIcons.trash, color: theme.mutedInkColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogPhotoPreview extends StatefulWidget {
  const _LogPhotoPreview({
    required this.theme,
    required this.label,
    required this.imageUrl,
  });

  final CompanyThemeData theme;
  final String label;
  final String imageUrl;

  @override
  State<_LogPhotoPreview> createState() => _LogPhotoPreviewState();
}

class _LogPhotoPreviewState extends State<_LogPhotoPreview> {
  Future<Uint8List?>? _localPhotoFuture;

  bool get _isLocalReference =>
      widget.imageUrl.startsWith('file:') ||
      widget.imageUrl.startsWith('exercise-web-photo:');

  @override
  void initState() {
    super.initState();
    _loadLocalPhoto();
  }

  @override
  void didUpdateWidget(covariant _LogPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _loadLocalPhoto();
  }

  void _loadLocalPhoto() {
    _localPhotoFuture = _isLocalReference
        ? PendingExerciseSyncService.instance.readPhoto(widget.imageUrl)
        : null;
  }

  void _openFullScreenImage(BuildContext context, Uint8List? localBytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(10),
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: localBytes == null
                  ? Image.network(
                      widget.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 72,
                            color: Colors.white54,
                          ),
                        );
                      },
                    )
                  : Image.memory(localBytes, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _localPhotoFuture;
    if (future != null) {
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) => _buildPreview(
          context,
          snapshot.data,
          isLoading: snapshot.connectionState != ConnectionState.done,
        ),
      );
    }
    return _buildPreview(context, null);
  }

  Widget _buildPreview(
    BuildContext context,
    Uint8List? localBytes, {
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: widget.theme.mutedInkColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: isLoading
              ? null
              : () => _openFullScreenImage(context, localBytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                isLoading
                    ? const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : localBytes == null
                        ? Image.network(
                            widget.imageUrl,
                            height: 72,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Image.memory(
                            localBytes,
                            height: 72,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.zoom_in_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
