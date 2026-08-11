import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_gallery_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
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
  static const Duration _photoUploadTimeout = Duration(seconds: 45);
  static final List<int> _durationHourOptions =
      List<int>.generate(24, (index) => index);
  static final List<int> _durationMinuteSecondOptions =
      List<int>.generate(60, (index) => index);

  final ActivityStreakService _activityStreakService = ActivityStreakService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _customTypeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ExerciseApiService _exerciseApi = ExerciseApiService.instance;
  final FastingNotificationService _notificationService =
      FastingNotificationService.instance;

  String _selectedType = _exerciseTypes.first;
  ExerciseDurationSelection _goalDurationSelection =
      const ExerciseDurationSelection(hours: 0, minutes: 5, seconds: 0);
  int _intensity = 2;
  DateTime? _sessionStartAt;
  DateTime? _sessionEndsAt;
  Duration? _stoppedElapsedDuration;
  String? _startPhotoUrl;
  String? _pendingEndPhotoUrl;
  bool _isUploadingStartPhoto = false;
  bool _isUploadingEndPhoto = false;
  bool _isStarting = false;
  bool _isSaving = false;
  bool _isLoadingLogs = true;
  bool _isRestoringSession = true;
  bool _hasAnnouncedGoalReached = false;
  String? _saveRecoveryError;
  Timer? _sessionTimer;
  Timer? _completionAlarmTimer;
  final AudioPlayer _alarmPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  bool _alarmAudioContextConfigured = false;
  List<Map<String, dynamic>> _todayLogs = [];

  String get _todayDate => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void dispose() {
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
    _restoreActiveSession();
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
      final prefs = await _prefs;
      final startMs = prefs.getInt(_sessionStartKey);
      if (startMs == null) return;

      final session = AuthService.instance.currentSession;
      final ownerId = prefs.getString(_sessionOwnerKey);
      if (session == null ||
          (ownerId != null && ownerId != session.id.toString())) {
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
        _goalDurationSelection =
            exerciseDurationSelectionFromDuration(goalDuration);
        _selectedType = selectedType;
        _customTypeController.text = customType;
        _intensity = intensity;
        _notesController.text = prefs.getString(_sessionNotesKey) ?? '';
        _startPhotoUrl = prefs.getString(_sessionStartPhotoKey);
        _pendingEndPhotoUrl = prefs.getString(_sessionEndPhotoKey);
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

  Future<void> _persistActiveSession() async {
    final prefs = await _prefs;
    if (!_isSessionActive) return;
    final userId = AuthService.instance.currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Exercise session requires a signed-in user.');
    }

    await prefs.setInt(
      _sessionStartKey,
      _sessionStartAt!.millisecondsSinceEpoch,
    );
    await prefs.setString(_sessionOwnerKey, userId);
    await prefs.setInt(
      _sessionGoalSecondsKey,
      _selectedGoalDuration.inSeconds,
    );
    await prefs.setInt(
      _sessionGoalKey,
      _selectedGoalDuration.inMinutes,
    );
    await prefs.setString(_sessionTypeKey, _selectedType);
    await prefs.setString(
      _sessionCustomTypeKey,
      _customTypeController.text.trim(),
    );
    await prefs.setInt(_sessionIntensityKey, _intensity);
    await prefs.setString(_sessionNotesKey, _notesController.text.trim());
    if (_startPhotoUrl != null && _startPhotoUrl!.isNotEmpty) {
      await prefs.setString(_sessionStartPhotoKey, _startPhotoUrl!);
    } else {
      await prefs.remove(_sessionStartPhotoKey);
    }
    if (_pendingEndPhotoUrl != null && _pendingEndPhotoUrl!.isNotEmpty) {
      await prefs.setString(_sessionEndPhotoKey, _pendingEndPhotoUrl!);
    } else {
      await prefs.remove(_sessionEndPhotoKey);
    }
    if (_stoppedElapsedDuration != null) {
      await prefs.setInt(
        _sessionStoppedDurationKey,
        boundedExerciseLogDuration(_stoppedElapsedDuration!).inSeconds,
      );
    } else {
      await prefs.remove(_sessionStoppedDurationKey);
    }
  }

  Future<void> _clearActiveSessionCache(
      [SharedPreferences? cachedPrefs]) async {
    final prefs = cachedPrefs ?? await _prefs;
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

  Future<String?> _captureExercisePhoto() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (pickedImage == null) return null;

    final imageUrl = await ImageStorageService.uploadImageFile(
      File(pickedImage.path),
    ).timeout(_photoUploadTimeout);
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception(
        ImageStorageService.lastError ?? 'Failed to upload image.',
      );
    }
    return imageUrl;
  }

  bool _matchesActiveSession(DateTime startedAt) =>
      _sessionStartAt?.isAtSameMomentAs(startedAt) ?? false;

  Future<void> _captureAndAttachStartPhoto(DateTime startedAt) async {
    try {
      final startPhotoUrl = await _captureExercisePhoto();
      if (!mounted ||
          !_matchesActiveSession(startedAt) ||
          startPhotoUrl == null) {
        return;
      }

      setState(() => _startPhotoUrl = startPhotoUrl);
      try {
        await _persistActiveSession();
      } catch (error) {
        debugPrint('Could not persist exercise start photo: $error');
      }
    } on TimeoutException {
      if (mounted && _matchesActiveSession(startedAt)) {
        _showMessage(
            'Start photo upload timed out. Your workout is still running.');
      }
    } catch (error) {
      debugPrint('Start photo capture failed: $error');
    } finally {
      if (mounted && _matchesActiveSession(startedAt)) {
        setState(() => _isUploadingStartPhoto = false);
      }
    }
  }

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

    final now = DateTime.now();
    try {
      unawaited(_stopCompletionAlarm());
      setState(() {
        _isStarting = true;
        _sessionStartAt = now;
        _sessionEndsAt = now.add(_selectedGoalDuration);
        _stoppedElapsedDuration = null;
        _startPhotoUrl = null;
        _pendingEndPhotoUrl = null;
        _hasAnnouncedGoalReached = false;
        _saveRecoveryError = null;
      });

      // Save the start before optional camera/upload work. A slow photo
      // upload can no longer delay or lose the timer itself.
      await _persistActiveSession();
      _startSessionTicker();
      if (!mounted || !_matchesActiveSession(now)) return;
      setState(() {
        _isStarting = false;
        _isUploadingStartPhoto = true;
      });
      unawaited(_syncStartedExerciseNotification(now));
      unawaited(_captureAndAttachStartPhoto(now));
      _showMessage(
        'Exercise started. We will alert you when the '
        '${formatExerciseDuration(_selectedGoalDuration)} goal is done.',
      );
    } catch (error) {
      _stopSessionTicker();
      try {
        await _clearActiveSessionCache();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _sessionStartAt = null;
          _sessionEndsAt = null;
          _stoppedElapsedDuration = null;
          _startPhotoUrl = null;
          _pendingEndPhotoUrl = null;
        });
        _showMessage('Could not start exercise. Please try again.');
      }
      debugPrint('Exercise start failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
          if (!_isSessionActive) {
            _isUploadingStartPhoto = false;
          }
        });
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

    final startedAt = _sessionStartAt!;
    final elapsedAtStop = _elapsedSessionTime();
    final logDuration = boundedExerciseLogDuration(elapsedAtStop);
    final durationWasCapped = exerciseLogDurationWasCapped(elapsedAtStop);
    final isFirstStopAttempt = _stoppedElapsedDuration == null;
    var exerciseStored = false;

    // Silence the alarm the instant Stop & save is tapped, not after
    // everything else below finishes. _captureExercisePhoto() alone can
    // wait on the user through the entire native camera UI, so leaving the
    // alarm stop until after it (and the network calls that follow) meant
    // the alarm kept blaring through all of that -- it looked like Stop
    // did nothing until something else (like leaving the screen) tore the
    // player down instead.
    unawaited(_stopCompletionAlarm());
    // Freeze the session at the member's Stop tap. A long photo/network
    // operation must not advance the clock or restart the completion alarm
    // while the member is deciding whether to retry or discard.
    _stopSessionTicker();
    unawaited(_clearExerciseNotification());

    setState(() {
      if (isFirstStopAttempt) {
        _stoppedElapsedDuration = elapsedAtStop;
      }
      _isUploadingEndPhoto = true;
      _saveRecoveryError = null;
    });
    try {
      if (isFirstStopAttempt) {
        try {
          await _persistActiveSession();
        } catch (error) {
          // The in-memory duration is still frozen for this attempt. Keep
          // the recovery controls usable even if local cache is unavailable.
          debugPrint('Could not persist stopped exercise duration: $error');
        }
      }

      // Same as the start photo: don't let a cancelled/failed camera
      // capture throw away an already-completed workout's data.
      var endPhotoUrl = _pendingEndPhotoUrl;
      if (endPhotoUrl == null || endPhotoUrl.isEmpty) {
        try {
          endPhotoUrl = await _captureExercisePhoto();
        } on TimeoutException {
          if (mounted && _matchesActiveSession(startedAt)) {
            _showMessage(
              'End photo upload timed out. You can still save this workout.',
            );
          }
        } catch (error) {
          debugPrint('End photo capture failed: $error');
        }
      }

      // The member may choose Discard while a native camera/upload is open.
      // Never let an older capture attach itself to a later workout.
      if (!mounted || !_matchesActiveSession(startedAt)) return;
      if (endPhotoUrl != null && endPhotoUrl.isNotEmpty) {
        setState(() => _pendingEndPhotoUrl = endPhotoUrl);
        try {
          await _persistActiveSession();
        } catch (error) {
          // The session is already persisted from Start; a failed optional
          // end-photo cache write must not make Stop unusable.
          debugPrint('Could not persist exercise end photo: $error');
        }
      }

      if (!mounted || !_matchesActiveSession(startedAt)) return;
      setState(() {
        _isUploadingEndPhoto = false;
        _isSaving = true;
      });
      await _exerciseApi.store(
        type: type,
        durationMinutes: exerciseLogDurationMinutes(logDuration),
        durationSeconds: logDuration.inSeconds,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startPhotoUrl: _startPhotoUrl,
        endPhotoUrl: endPhotoUrl,
        date: _todayDate,
      );
      exerciseStored = true;

      // The API is the authoritative save. Once it succeeds, clear the
      // replayable local session before any secondary refresh/reward work so
      // a transient follow-up error cannot make a retry create a duplicate.
      await _clearExerciseNotification();
      try {
        await _clearActiveSessionCache();
      } catch (error) {
        debugPrint('Could not clear saved exercise session: $error');
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
        _hasAnnouncedGoalReached = false;
        _saveRecoveryError = null;
        _isSaving = false;
        _isUploadingEndPhoto = false;
      });
      unawaited(_loadTodayLogs());
      List<ActivityStreakMilestone> unlockedRewards =
          <ActivityStreakMilestone>[];
      try {
        unlockedRewards = await _recordExerciseStreak(session.id.toString());
      } catch (error) {
        // Logging the workout already succeeded. Rewards are secondary and
        // must never turn a saved workout into a misleading retry state.
        debugPrint('Exercise reward update failed after save: $error');
      }
      if (!mounted) return;
      _showMessage(
        unlockedRewards.isEmpty
            ? (durationWasCapped
                ? 'Exercise logged at the 24-hour maximum.'
                : 'Exercise logged.')
            : 'Exercise medal unlocked: ${unlockedRewards.last.title}',
      );
    } catch (error) {
      if (!mounted) return;
      if (exerciseStored) {
        debugPrint('Exercise follow-up failed after save: $error');
        return;
      }
      final durationNote = durationWasCapped
          ? ' The duration will be saved at the 24-hour maximum.'
          : '';
      final recoveryMessage =
          'Could not save your workout. It is still on this device. '
          'Retry save when you are connected, or discard it.$durationNote';
      setState(() => _saveRecoveryError = recoveryMessage);
      _showMessage(recoveryMessage);
      debugPrint('Exercise save failed: $error');
    } finally {
      if (mounted && _matchesActiveSession(startedAt)) {
        setState(() {
          _isSaving = false;
          _isUploadingEndPhoto = false;
        });
      }
    }
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
      _hasAnnouncedGoalReached = false;
      _isStarting = false;
      _isUploadingStartPhoto = false;
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

  Future<List<ActivityStreakMilestone>> _recordExerciseStreak(
    String userId,
  ) async {
    try {
      return await _activityStreakService.recordCompletedSession(
        userId: userId,
        type: ActivityStreakType.exercise,
      );
    } catch (error) {
      debugPrint('Exercise streak update failed: $error');
      return <ActivityStreakMilestone>[];
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
              icon: (_isStarting ||
                      _isSaving ||
                      _isUploadingEndPhoto ||
                      (_isSessionActive
                          ? _isUploadingEndPhoto
                          : _isUploadingStartPhoto))
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
                    ? 'Starting...'
                    : _isSaving
                        ? 'Saving...'
                        : _isUploadingEndPhoto
                            ? 'Adding end photo...'
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
            if (_isUploadingStartPhoto) ...[
              const SizedBox(height: 10),
              Text(
                'Adding your optional start photo…',
                style: TextStyle(
                  color: theme.mutedInkColor,
                  fontWeight: FontWeight.w700,
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

class _LogPhotoPreview extends StatelessWidget {
  const _LogPhotoPreview({
    required this.theme,
    required this.label,
    required this.imageUrl,
  });

  final CompanyThemeData theme;
  final String label;
  final String imageUrl;

  void _openFullScreenImage(BuildContext context) {
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
              child: Image.network(
                imageUrl,
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
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.mutedInkColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _openFullScreenImage(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Image.network(
                  imageUrl,
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
