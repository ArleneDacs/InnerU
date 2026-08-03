import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';
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
  String? _startPhotoUrl;
  bool _isUploadingStartPhoto = false;
  bool _isUploadingEndPhoto = false;
  bool _isSaving = false;
  bool _isLoadingLogs = true;
  bool _hasAnnouncedGoalReached = false;
  Timer? _sessionTimer;
  Timer? _completionAlarmTimer;
  List<Map<String, dynamic>> _todayLogs = [];

  String get _todayDate => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _completionAlarmTimer?.cancel();
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

  bool get _isSessionActive => _sessionStartAt != null && _sessionEndsAt != null;

  Duration _elapsedSessionTime() {
    if (_sessionStartAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_sessionStartAt!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration _remainingSessionTime() {
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
    final elapsed =
        DateTime.now().difference(_sessionStartAt!).inSeconds.clamp(0, total);
    return elapsed / total;
  }

  Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  Future<void> _restoreActiveSession() async {
    try {
      final prefs = await _prefs;
      final startMs = prefs.getInt(_sessionStartKey);
      if (startMs == null) return;

      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final totalSeconds =
          prefs.getInt(_sessionGoalSecondsKey) ??
          Duration(minutes: prefs.getInt(_sessionGoalKey) ?? 5).inSeconds;
      final goalDuration = Duration(seconds: totalSeconds);
      final end = start.add(goalDuration);

      if (!mounted) return;
      setState(() {
        _sessionStartAt = start;
        _sessionEndsAt = end;
        _goalDurationSelection =
            exerciseDurationSelectionFromDuration(goalDuration);
        _selectedType = prefs.getString(_sessionTypeKey) ?? _selectedType;
        _customTypeController.text = prefs.getString(_sessionCustomTypeKey) ?? '';
        _intensity = prefs.getInt(_sessionIntensityKey) ?? _intensity;
        _notesController.text = prefs.getString(_sessionNotesKey) ?? '';
        _startPhotoUrl = prefs.getString(_sessionStartPhotoKey);
        _hasAnnouncedGoalReached = false;
      });

      _startSessionTicker();
      await _syncExerciseNotification();
    } catch (error) {
      debugPrint('Failed to restore exercise session: $error');
    }
  }

  Future<void> _persistActiveSession() async {
    final prefs = await _prefs;
    if (!_isSessionActive) return;

    await prefs.setInt(
      _sessionStartKey,
      _sessionStartAt!.millisecondsSinceEpoch,
    );
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
  }

  Future<void> _clearActiveSessionCache() async {
    final prefs = await _prefs;
    await prefs.remove(_sessionStartKey);
    await prefs.remove(_sessionGoalSecondsKey);
    await prefs.remove(_sessionGoalKey);
    await prefs.remove(_sessionTypeKey);
    await prefs.remove(_sessionCustomTypeKey);
    await prefs.remove(_sessionIntensityKey);
    await prefs.remove(_sessionNotesKey);
    await prefs.remove(_sessionStartPhotoKey);
  }

  void _startSessionTicker() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _remainingSessionTime();
      if (remaining == Duration.zero && !_hasAnnouncedGoalReached) {
        _hasAnnouncedGoalReached = true;
        _playCompletionAlarm();
        _showMessage('Exercise goal reached. Great work!');
      }
      setState(() {});
    });
  }

  // Rings a repeating system alert + haptic burst once the goal duration is
  // hit, and keeps ringing indefinitely -- like an actual alarm -- until
  // the workout is explicitly stopped and saved (or a new session starts).
  // _stopExerciseSession, _startExerciseSession, and dispose() all cancel
  // _completionAlarmTimer, which is the only thing that ends this loop.
  void _playCompletionAlarm() {
    _completionAlarmTimer?.cancel();

    void ring() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }

    ring();
    _completionAlarmTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => ring(),
    );
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
    if (_selectedType == 'Other' && custom.isNotEmpty) return custom;
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
    );
    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception(
        ImageStorageService.lastError ?? 'Failed to upload image.',
      );
    }
    return imageUrl;
  }

  Future<void> _startExerciseSession() async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSaving || _isSessionActive) return;

    final type = _effectiveType();
    if (type.trim().isEmpty) {
      _showMessage('Enter an exercise type.');
      return;
    }
    if (_selectedGoalDuration <= Duration.zero) {
      _showMessage('Pick an exercise duration first.');
      return;
    }

    setState(() {
      _isUploadingStartPhoto = true;
    });

    try {
      // A cancelled/failed photo should not block starting the workout —
      // the photo is a nice-to-have on the log, not a required field.
      String? startPhotoUrl;
      try {
        startPhotoUrl = await _captureExercisePhoto();
      } catch (error) {
        debugPrint('Start photo capture failed: $error');
      }

      _completionAlarmTimer?.cancel();
      final now = DateTime.now();
      setState(() {
        _selectedType = type;
        _sessionStartAt = now;
        _sessionEndsAt = now.add(_selectedGoalDuration);
        _startPhotoUrl = startPhotoUrl;
        _hasAnnouncedGoalReached = false;
      });

      await _persistActiveSession();
      _startSessionTicker();
      final notificationsReady = await _syncExerciseNotification();
      final startedMessage = notificationsReady
          ? 'Exercise started. We will alert you when the ${formatExerciseDuration(_selectedGoalDuration)} goal is done.'
          : 'Exercise started, but completion alerts are unavailable right now.';
      _showMessage(
        startPhotoUrl == null
            ? '$startedMessage (no start photo saved.)'
            : startedMessage,
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not start exercise. Please try again.');
      }
      debugPrint('Exercise start failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingStartPhoto = false;
        });
      }
    }
  }

  Future<void> _stopExerciseSession() async {
    final session = AuthService.instance.currentSession;
    if (session == null || _isSaving || !_isSessionActive) return;

    final type = _effectiveType();
    if (type.trim().isEmpty) {
      _showMessage('Enter an exercise type.');
      return;
    }

    setState(() {
      _isUploadingEndPhoto = true;
      _isSaving = true;
    });
    try {
      // Same as the start photo: don't let a cancelled/failed camera
      // capture throw away an already-completed workout's data.
      String? endPhotoUrl;
      try {
        endPhotoUrl = await _captureExercisePhoto();
      } catch (error) {
        debugPrint('End photo capture failed: $error');
      }

      final elapsed = _elapsedSessionTime();
      final actualSeconds = math.max(1, elapsed.inSeconds);
      final actualMinutes = math.max(1, (actualSeconds / 60).round());
      await _exerciseApi.store(
        type: type,
        durationMinutes: actualMinutes,
        durationSeconds: actualSeconds,
        intensity: _intensity,
        notes: _notesController.text.trim(),
        startPhotoUrl: _startPhotoUrl,
        endPhotoUrl: endPhotoUrl,
        date: _todayDate,
      );
      await _loadTodayLogs();
      final unlockedRewards = await _recordExerciseStreak(session.id.toString());
      await _clearExerciseNotification();
      await _clearActiveSessionCache();
      _completionAlarmTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _selectedType = _exerciseTypes.first;
        _goalDurationSelection =
            const ExerciseDurationSelection(hours: 0, minutes: 5, seconds: 0);
        _intensity = 2;
        _customTypeController.clear();
        _notesController.clear();
        _startPhotoUrl = null;
        _sessionStartAt = null;
        _sessionEndsAt = null;
        _hasAnnouncedGoalReached = false;
      });
      _showMessage(
        unlockedRewards.isEmpty
            ? 'Exercise logged.'
            : 'Exercise medal unlocked: ${unlockedRewards.last.title}',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save exercise. Please try again.');
      debugPrint('Exercise save failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isUploadingEndPhoto = false;
        });
      }
    }
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
              : _isLoadingLogs
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      children: [
                        _buildSummary(theme, _todayLogs),
                        const SizedBox(height: 16),
                        _buildLogger(theme),
                        const SizedBox(height: 18),
                        _buildTodayLogs(theme, _todayLogs),
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
    final controlsDisabled = _isSaving || _isSessionActive;
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
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving
                  ? null
                  : _isSessionActive
                      ? _stopExerciseSession
                      : _startExerciseSession,
              icon: (_isSaving ||
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
                _isSaving
                    ? 'Saving...'
                    : _isSessionActive
                        ? (_remainingSessionTime() == Duration.zero
                            ? 'Stop & save'
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

  Widget _buildSessionStatus(CompanyThemeData theme) {
    final active = _isSessionActive;
    final remaining = _remainingSessionTime();
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
                  active ? 'Workout in progress' : 'Ready to start',
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                active ? '$percent%' : formatExerciseDuration(_selectedGoalDuration),
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
              'Remaining ${formatExerciseDuration(remaining)}',
              style: TextStyle(
                color: theme.mutedInkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_startPhotoUrl != null) ...[
              const SizedBox(height: 12),
              _LogPhotoPreview(
                theme: theme,
                label: 'Start photo',
                imageUrl: _startPhotoUrl!,
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
          segments: [
            for (var i = 0; i < labels.length; i++)
              ButtonSegment<int>(
                value: i + 1,
                label: Text(labels[i]),
                icon: Icon(
                  i == 0
                      ? CupertinoIcons.wind
                      : i == 1
                          ? CupertinoIcons.flame
                          : CupertinoIcons.bolt_fill,
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
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imageUrl,
            height: 72,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}
