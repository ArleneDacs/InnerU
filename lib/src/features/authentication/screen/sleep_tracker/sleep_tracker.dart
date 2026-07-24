import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SleepTracker extends StatefulWidget {
  const SleepTracker({super.key});

  @override
  State<SleepTracker> createState() => _SleepTrackerState();
}

class _SleepTrackerState extends State<SleepTracker>
    with WidgetsBindingObserver {
  static const _modeKey = 'sleep_tracker_mode';
  static const _goalKey = 'sleep_tracker_goal_hours';
  static const _goalMinutesKey = 'sleep_tracker_goal_minutes';
  static const _bedtimeHourKey = 'sleep_tracker_bedtime_hour';
  static const _bedtimeMinuteKey = 'sleep_tracker_bedtime_minute';
  static const _activeStartKey = 'sleep_tracker_active_start';
  static const _historyKey = 'sleep_tracker_history';

  final List<String> _modeOptions = const ['Alarm', 'Vibrate', 'Silent'];

  String _selectedMode = 'Alarm';
  Duration _selectedSleepGoal = const Duration(hours: 8);
  TimeOfDay _selectedBedtime = const TimeOfDay(hour: 22, minute: 0);
  DateTime? _activeSleepStart;
  List<_SleepSession> _history = const [];
  bool _isLoading = true;
  bool _isSavingSettings = false;
  Timer? _ticker;
  Timer? _goalReachedTimer;
  Timer? _completionAlarmTimer;
  bool _goalReachedAlertShown = false;
  int _lastOngoingNotificationMinute = -1;
  late final AudioPlayer _sleepAlarmPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  bool _isSleepAlarmPlaying = false;
  StreamSubscription<void>? _sleepAlarmStoppedSubscription;

  String get _userId =>
      AuthService.instance.currentSession?.id.toString() ?? 'guest';

  String _scopedKey(String key) => '${key}_$_userId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sleepAlarmStoppedSubscription =
        FastingNotificationService.instance.onSleepAlarmStopped.listen((_) {
      if (!mounted) return;
      _goalReachedAlertShown = true;
      _goalReachedTimer?.cancel();
      unawaited(_stopSleepAlarmMusic());
      unawaited(FastingNotificationService.instance.cancelSleepAlarmBurst());
    });
    _loadSleepData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepAlarmStoppedSubscription?.cancel();
    _ticker?.cancel();
    _goalReachedTimer?.cancel();
    _completionAlarmTimer?.cancel();
    unawaited(_stopSleepAlarmMusic());
    unawaited(_sleepAlarmPlayer.dispose());
    super.dispose();
  }

  Future<void> _loadSleepData() async {
    _ticker?.cancel();
    _goalReachedTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final historyStrings =
        prefs.getStringList(_scopedKey(_historyKey)) ?? const [];
    final activeStartString = prefs.getString(_scopedKey(_activeStartKey));

    if (!mounted) return;

    setState(() {
      _selectedMode = prefs.getString(_scopedKey(_modeKey)) ?? _selectedMode;
      final storedGoalHours = prefs.getInt(_scopedKey(_goalKey));
      if (storedGoalHours != null) {
        _selectedSleepGoal = Duration(
          hours: storedGoalHours,
          minutes: prefs.getInt(_scopedKey(_goalMinutesKey)) ?? 0,
        );
      }
      _selectedBedtime = TimeOfDay(
        hour:
            prefs.getInt(_scopedKey(_bedtimeHourKey)) ?? _selectedBedtime.hour,
        minute: prefs.getInt(_scopedKey(_bedtimeMinuteKey)) ??
            _selectedBedtime.minute,
      );
      _activeSleepStart = activeStartString == null
          ? null
          : DateTime.tryParse(activeStartString);
      _history = historyStrings
          .map(_SleepSession.fromJsonString)
          .whereType<_SleepSession>()
          .toList();
      _isLoading = false;
    });

    if (_activeSleepStart != null) {
      _startTicker();
      await _syncActiveSleepNotifications();
      _armGoalReachedAlarm();
    } else {
      await _syncInactiveSleepNotifications();
      await _scheduleBedtimeReminder();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSleepData());
    }
  }

  Future<void> _syncInactiveSleepNotifications() async {
    await FastingNotificationService.instance.cancelSleepWakeNotification();
    await FastingNotificationService.instance.cancelSleepAlarmBurst();
    await FastingNotificationService.instance.cancelSleepOngoingNotification();
  }

  Future<void> _syncActiveSleepNotifications() async {
    await FastingNotificationService.instance.cancelDailySleepBedtimeReminder();
    await _scheduleWakeNotification();
    await _showSleepOngoingNotification();
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSavingSettings = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey(_modeKey), _selectedMode);
    await prefs.setInt(_scopedKey(_goalKey), _selectedSleepGoal.inHours);
    await prefs.setInt(
      _scopedKey(_goalMinutesKey),
      _selectedSleepGoal.inMinutes % 60,
    );
    await prefs.setInt(_scopedKey(_bedtimeHourKey), _selectedBedtime.hour);
    await prefs.setInt(_scopedKey(_bedtimeMinuteKey), _selectedBedtime.minute);
    if (_activeSleepStart == null) {
      await _scheduleBedtimeReminder();
    } else {
      await _syncActiveSleepNotifications();
      _armGoalReachedAlarm();
    }

    if (!mounted) return;
    setState(() {
      _isSavingSettings = false;
    });
    _showSnackBar('Sleep settings saved.');
  }

  Future<void> _startSleepSession() async {
    final start = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey(_activeStartKey), start.toIso8601String());

    setState(() {
      _activeSleepStart = start;
      _goalReachedAlertShown = false;
      _lastOngoingNotificationMinute = -1;
    });
    _startTicker();
    await FastingNotificationService.instance.cancelDailySleepBedtimeReminder();
    await _showSleepOngoingNotification();
    await _scheduleWakeNotification();
    _armGoalReachedAlarm();
    _showSnackBar('Sleep session started. Rest well.');
  }

  Future<void> _endSleepSession() async {
    final start = _activeSleepStart;
    if (start == null) return;

    final end = DateTime.now();
    final session = _SleepSession(
      start: start,
      end: end,
      goalHours: _selectedSleepGoal.inHours,
    );

    final updatedHistory = [session, ..._history].take(14).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey(_activeStartKey));
    await prefs.setStringList(
      _scopedKey(_historyKey),
      updatedHistory.map((item) => item.toJsonString()).toList(),
    );

    _ticker?.cancel();
    _goalReachedTimer?.cancel();
    _completionAlarmTimer?.cancel();
    _goalReachedAlertShown = false;
    _lastOngoingNotificationMinute = -1;
    await _stopSleepAlarmMusic();
    await FastingNotificationService.instance.cancelSleepWakeNotification();
    await FastingNotificationService.instance.cancelSleepAlarmBurst();
    await FastingNotificationService.instance.cancelSleepOngoingNotification();
    await _scheduleBedtimeReminder();

    setState(() {
      _activeSleepStart = null;
      _history = updatedHistory;
    });

    _showSnackBar(
      'Sleep session saved: ${_formatDuration(session.duration)}.',
    );
    await _promptShareSleepSession(session);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _checkForGoalCompletion();
        final start = _activeSleepStart;
        if (start != null) {
          final elapsed = DateTime.now().difference(start);
          final elapsedMinute = elapsed.inMinutes;
          if (elapsedMinute != _lastOngoingNotificationMinute) {
            _lastOngoingNotificationMinute = elapsedMinute;
            _showSleepOngoingNotification();
          }
        }
      }
    });
  }

  void _armGoalReachedAlarm() {
    _goalReachedTimer?.cancel();

    final start = _activeSleepStart;
    if (start == null) return;

    final remaining =
        _selectedSleepGoal - DateTime.now().difference(start);
    if (remaining <= Duration.zero) {
      _checkForGoalCompletion();
      return;
    }

    _goalReachedTimer = Timer(remaining, () {
      if (mounted) {
        _checkForGoalCompletion();
      }
    });
  }

  void _checkForGoalCompletion() {
    final start = _activeSleepStart;
    if (start == null || _goalReachedAlertShown) return;

    final elapsed = DateTime.now().difference(start);
    if (elapsed < _selectedSleepGoal) return;

    _goalReachedAlertShown = true;
    _goalReachedTimer?.cancel();
    _ticker?.cancel();
    _lastOngoingNotificationMinute = -1;
    unawaited(
        FastingNotificationService.instance.cancelSleepOngoingNotification());
    // The app is in the foreground playing the alarm live -- the
    // background notification burst would just be redundant now.
    unawaited(FastingNotificationService.instance.cancelSleepAlarmBurst());
    unawaited(_playCompletionAlarm());
    unawaited(_showGoalReachedDialog());
  }

  Future<void> _playCompletionAlarm() async {
    _completionAlarmTimer?.cancel();
    _completionAlarmTimer = null;

    try {
      await _sleepAlarmPlayer.stop();
      await _sleepAlarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _sleepAlarmPlayer.play(
        AssetSource('audio/Night_Firepit.mp3'),
        volume: 1.0,
      );
      _isSleepAlarmPlaying = true;
      HapticFeedback.mediumImpact();
    } catch (error) {
      debugPrint('Sleep alarm music failed: $error');
    }
  }

  Future<void> _stopSleepAlarmMusic() async {
    if (!_isSleepAlarmPlaying) return;
    try {
      await _sleepAlarmPlayer.stop();
      await _sleepAlarmPlayer.setReleaseMode(ReleaseMode.release);
    } catch (error) {
      debugPrint('Stopping sleep alarm music failed: $error');
    } finally {
      _isSleepAlarmPlaying = false;
    }
  }

  Future<void> _promptShareSleepSession(_SleepSession session) async {
    if (!mounted) return;

    final shouldShare = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Share sleep session?'),
          content: Text(
            'You slept for ${_formatDuration(session.duration)}. Would you like to share this milestone to the community?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Done'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Share'),
            ),
          ],
        );
      },
    );

    if (shouldShare != true || !mounted) return;

    final memoryNote = Note(
      id: '',
      userId: '',
      username: '',
      title: 'Sleep Milestone',
      note: [
        {
          'type': 'text',
          'value':
              'I completed a sleep session of ${_formatDuration(session.duration)} and wanted to share this restful milestone with the community.',
        },
      ],
      createdAt: DateTime.now(),
      category: 'Learning',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesType(
          note: memoryNote,
          initialCategory: 'Learning',
          openCommunityAfterPost: true,
        ),
      ),
    );
  }

  Future<void> _showGoalReachedDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Wake up'),
          content: Text(
            'Your ${_formatDuration(_selectedSleepGoal)} sleep goal is complete.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _endSleepSession();
              },
              child: const Text('End sleep'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _scheduleBedtimeReminder() async {
    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance.scheduleDailySleepBedtimeReminder(
      hour: _selectedBedtime.hour,
      minute: _selectedBedtime.minute,
    );
  }

  Future<void> _scheduleWakeNotification() async {
    final start = _activeSleepStart;
    if (start == null) return;

    final wakesAt = start.add(_selectedSleepGoal);
    await FastingNotificationService.instance.ensurePermissions();

    if (_selectedMode == 'Alarm') {
      // A single notification is too easy to sleep through and its sound
      // can't loop -- the repeating alarm burst is what actually behaves
      // like an alarm clock while the phone is locked or backgrounded.
      await FastingNotificationService.instance.cancelSleepWakeNotification();
      await FastingNotificationService.instance.scheduleSleepAlarmBurst(
        wakesAt: wakesAt,
        goalHours: _selectedSleepGoal.inHours,
      );
    } else {
      await FastingNotificationService.instance.cancelSleepAlarmBurst();
      await FastingNotificationService.instance.scheduleSleepWakeNotification(
        wakesAt: wakesAt,
        goalHours: _selectedSleepGoal.inHours,
        mode: _selectedMode,
      );
    }
  }

  Future<void> _showSleepOngoingNotification() async {
    final start = _activeSleepStart;
    if (start == null) return;

    final elapsed = DateTime.now().difference(start);
    final remaining = _selectedSleepGoal - elapsed;

    await FastingNotificationService.instance.showSleepOngoingNotification(
      elapsed: elapsed.isNegative ? Duration.zero : elapsed,
      remaining: remaining.isNegative ? Duration.zero : remaining,
      goalHours: _selectedSleepGoal.inHours,
    );
  }

  Future<void> _pickBedtime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedBedtime,
    );

    if (pickedTime == null) return;

    setState(() {
      _selectedBedtime = pickedTime;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final activeDuration = _activeSleepStart == null
        ? Duration.zero
        : now.difference(_activeSleepStart!);
    final latestSession = _history.isEmpty ? null : _history.first;
    final weeklyAverage = _history.isEmpty
        ? 0.0
        : _history
                .take(7)
                .map((session) => session.duration.inMinutes / 60)
                .reduce((a, b) => a + b) /
            _history.take(7).length;
    final goalMinutes = _selectedSleepGoal.inMinutes;
    final progress = _activeSleepStart == null || goalMinutes == 0
        ? 0.0
        : (activeDuration.inMinutes / goalMinutes).clamp(0.0, 1.0);

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);

              return Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                appBar: AppBar(
                  backgroundColor: companyTheme.surfaceColor,
                  foregroundColor: companyTheme.inkColor,
                  iconTheme: IconThemeData(color: companyTheme.inkColor),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    'Sleep Tracker',
                    style: TextStyle(
                      color: companyTheme.inkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                body: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary
                                      .withValues(alpha: 0.20),
                                  theme.colorScheme.secondary
                                      .withValues(alpha: 0.24),
                                  theme.colorScheme.surface,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Sleep Monitoring',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _activeSleepStart == null
                                            ? 'Set your bedtime, start tracking, and the session will keep running locally even offline until you end sleep.'
                                            : 'Your sleep session is running locally. Keep the screen closed and come back when you wake up.',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _statChip(
                                            CupertinoIcons.moon_stars_fill,
                                            'Goal',
                                            _formatDuration(_selectedSleepGoal),
                                          ),
                                          _statChip(
                                            CupertinoIcons.clock_fill,
                                            'Bedtime',
                                            _selectedBedtime.format(context),
                                          ),
                                          _statChip(
                                            CupertinoIcons.chart_bar_alt_fill,
                                            '7-day avg',
                                            weeklyAverage == 0
                                                ? '--'
                                                : '${weeklyAverage.toStringAsFixed(1)}h',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Image.asset(
                                  'assets/images/sleeping.png',
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tonight\'s Plan',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _dropdownSettingTile<String>(
                                        title: 'Wake notification',
                                        value: _selectedMode,
                                        items: _modeOptions,
                                        labelBuilder: (mode) => mode,
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(() {
                                            _selectedMode = value;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _bedtimeSettingTile(
                                        timeLabel:
                                            _selectedBedtime.format(context),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _sleepGoalSettingTile(companyTheme: companyTheme),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isSavingSettings
                                        ? null
                                        : _saveSettings,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF3D4E73),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text(
                                      _isSavingSettings
                                          ? 'Saving...'
                                          : 'Save settings',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Active Session',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (_activeSleepStart != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5EA),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Tracking now',
                                          style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _activeSleepStart == null
                                      ? 'No active sleep session yet.'
                                      : _formatDuration(activeDuration),
                                  style:
                                      theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _activeSleepStart == null
                                      ? 'Tap Start sleep when you are heading to bed.'
                                      : 'Started at ${DateFormat('h:mm a').format(_activeSleepStart!)}',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 12,
                                    backgroundColor: const Color(0xFFEAE6DE),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF788DB7),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _activeSleepStart == null
                                      ? 'Goal progress will appear while tracking.'
                                      : '${(progress * 100).round()}% of your ${_formatDuration(_selectedSleepGoal)} goal',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.62),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _activeSleepStart == null
                                            ? _startSleepSession
                                            : null,
                                        icon: const Icon(
                                            CupertinoIcons.moon_fill),
                                        label: const Text('Start sleep'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF2F3442),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _activeSleepStart == null
                                            ? null
                                            : _endSleepSession,
                                        icon: const Icon(
                                            CupertinoIcons.sun_max_fill),
                                        label: const Text('End sleep'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              theme.colorScheme.onSurface,
                                          side: BorderSide(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.55),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _sleepInsightRow(
                                  'Recommended wake-up',
                                  _formatRecommendedWakeTime(),
                                ),
                                const SizedBox(height: 8),
                                _sleepInsightRow(
                                  'Latest result',
                                  latestSession == null
                                      ? 'No sessions saved yet'
                                      : latestSession.qualityLabel,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Recent Sleep History',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (_history.isEmpty)
                                  Text(
                                    'No sleep sessions yet. Start one tonight to build your history.',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.62),
                                    ),
                                  )
                                else
                                  ..._history.map((session) {
                                    final hitGoal =
                                        session.duration.inMinutes >=
                                            session.goalHours * 60;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: hitGoal
                                                  ? const Color(0xFFE7F5EA)
                                                  : const Color(0xFFFFF0E8),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              hitGoal
                                                  ? CupertinoIcons
                                                      .check_mark_circled_solid
                                                  : CupertinoIcons
                                                      .moon_zzz_fill,
                                              color: hitGoal
                                                  ? const Color(0xFF2E7D32)
                                                  : const Color(0xFFCC7A00),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _formatDuration(
                                                      session.duration),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: theme
                                                        .colorScheme.onSurface,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${DateFormat('MMM d, h:mm a').format(session.start)} to ${DateFormat('h:mm a').format(session.end)}',
                                                  style: TextStyle(
                                                    color: theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: 0.62),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            session.qualityLabel,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: hitGoal
                                                  ? const Color(0xFF2E7D32)
                                                  : const Color(0xFFCC7A00),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        );
      },
    );
  }

  BoxDecoration _cardDecoration() {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? const Color(0xFF9DB2DF) : const Color(0xFF3D4E73),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingContainer({
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _dropdownSettingTile<T>({
    required String title,
    required T value,
    required List<T> items,
    required String Function(T value) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    return _settingContainer(
      title: title,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: theme.colorScheme.surface,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
          ),
          selectedItemBuilder: (context) {
            return items.map((item) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  labelBuilder(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              );
            }).toList();
          },
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(
                labelBuilder(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _bedtimeSettingTile({
    required String timeLabel,
  }) {
    return _settingContainer(
      title: 'Bedtime',
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                timeLabel,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _pickBedtime,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3D4E73),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Change',
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSleepGoal(CompanyThemeData companyTheme) async {
    Duration tempGoal = _selectedSleepGoal;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: companyTheme.surfaceColor,
      builder: (sheetContext) {
        return SizedBox(
          height: 250,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness:
                  companyTheme.isDark ? Brightness.dark : Brightness.light,
              primaryColor: companyTheme.primaryColor,
            ),
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hm,
              initialTimerDuration: _selectedSleepGoal,
              onTimerDurationChanged: (Duration newDuration) {
                tempGoal = newDuration;
              },
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _selectedSleepGoal = tempGoal;
    });
  }

  Widget _sleepGoalSettingTile({required CompanyThemeData companyTheme}) {
    return _settingContainer(
      title: 'Sleep goal',
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                _formatDuration(_selectedSleepGoal),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _pickSleepGoal(companyTheme),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3D4E73),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Change',
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sleepInsightRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  String _formatRecommendedWakeTime() {
    final now = DateTime.now();
    final bedtimeToday = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedBedtime.hour,
      _selectedBedtime.minute,
    );
    final bedtime = bedtimeToday.isAfter(now)
        ? bedtimeToday
        : bedtimeToday.add(const Duration(days: 1));
    final recommendedWake = bedtime.add(_selectedSleepGoal);
    return DateFormat('MMM d, h:mm a').format(recommendedWake);
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}

class _SleepSession {
  const _SleepSession({
    required this.start,
    required this.end,
    required this.goalHours,
  });

  final DateTime start;
  final DateTime end;
  final int goalHours;

  Duration get duration => end.difference(start);

  String get qualityLabel {
    final hours = duration.inMinutes / 60;
    if (hours >= goalHours) return 'Goal hit';
    if (hours >= goalHours - 1) return 'Almost there';
    return 'Short sleep';
  }

  String toJsonString() {
    return jsonEncode({
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'goalHours': goalHours,
    });
  }

  static _SleepSession? fromJsonString(String source) {
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      final start = DateTime.tryParse(map['start'] as String? ?? '');
      final end = DateTime.tryParse(map['end'] as String? ?? '');
      final goalHours = map['goalHours'] as int? ?? 8;
      if (start == null || end == null) return null;
      return _SleepSession(
        start: start,
        end: end,
        goalHours: goalHours,
      );
    } catch (_) {
      return null;
    }
  }
}
