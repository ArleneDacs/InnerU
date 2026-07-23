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

class _SleepTrackerState extends State<SleepTracker> {
  static const _modeKey = 'sleep_tracker_mode';
  static const _goalKey = 'sleep_tracker_goal_hours';
  static const _bedtimeHourKey = 'sleep_tracker_bedtime_hour';
  static const _bedtimeMinuteKey = 'sleep_tracker_bedtime_minute';
  static const _activeStartKey = 'sleep_tracker_active_start';
  static const _historyKey = 'sleep_tracker_history';

  final List<String> _modeOptions = const ['Alarm', 'Vibrate', 'Silent'];
  final List<int> _goalOptions = List<int>.generate(12, (index) => index + 1);

  String _selectedMode = 'Alarm';
  int _selectedSleepGoal = 8;
  TimeOfDay _selectedBedtime = const TimeOfDay(hour: 22, minute: 0);
  DateTime? _activeSleepStart;
  List<_SleepSession> _history = const [];
  bool _isLoading = true;
  bool _isSavingSettings = false;
  Timer? _ticker;
  Timer? _goalReachedTimer;
  Timer? _completionAlarmTimer;
  bool _goalReachedAlertShown = false;
  late final AudioPlayer _sleepAlarmPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  bool _isSleepAlarmPlaying = false;

  String get _userId =>
      AuthService.instance.currentSession?.id.toString() ?? 'guest';

  String _scopedKey(String key) => '${key}_$_userId';

  @override
  void initState() {
    super.initState();
    _loadSleepData();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _goalReachedTimer?.cancel();
    _completionAlarmTimer?.cancel();
    unawaited(_stopSleepAlarmMusic());
    unawaited(_sleepAlarmPlayer.dispose());
    super.dispose();
  }

  Future<void> _loadSleepData() async {
    final prefs = await SharedPreferences.getInstance();
    final historyStrings =
        prefs.getStringList(_scopedKey(_historyKey)) ?? const [];
    final activeStartString = prefs.getString(_scopedKey(_activeStartKey));

    if (!mounted) return;

    setState(() {
      _selectedMode = prefs.getString(_scopedKey(_modeKey)) ?? _selectedMode;
      _selectedSleepGoal =
          prefs.getInt(_scopedKey(_goalKey)) ?? _selectedSleepGoal;
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

  Future<void> _syncInactiveSleepNotifications() async {
    await FastingNotificationService.instance.cancelSleepWakeNotification();
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
    await prefs.setInt(_scopedKey(_goalKey), _selectedSleepGoal);
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
      goalHours: _selectedSleepGoal,
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
    await _stopSleepAlarmMusic();
    await FastingNotificationService.instance.cancelSleepWakeNotification();
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
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
        _showSleepOngoingNotification();
        _checkForGoalCompletion();
      }
    });
  }

  void _armGoalReachedAlarm() {
    _goalReachedTimer?.cancel();

    final start = _activeSleepStart;
    if (start == null) return;

    final remaining =
        Duration(hours: _selectedSleepGoal) - DateTime.now().difference(start);
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
    if (elapsed < Duration(hours: _selectedSleepGoal)) return;

    _goalReachedAlertShown = true;
    _goalReachedTimer?.cancel();
    _ticker?.cancel();
    unawaited(
        FastingNotificationService.instance.cancelSleepOngoingNotification());
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
            'Your $_selectedSleepGoal-hour sleep goal is complete.',
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

    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance.scheduleSleepWakeNotification(
      wakesAt: start.add(Duration(hours: _selectedSleepGoal)),
      goalHours: _selectedSleepGoal,
      mode: _selectedMode,
    );
  }

  Future<void> _showSleepOngoingNotification() async {
    final start = _activeSleepStart;
    if (start == null) return;

    final elapsed = DateTime.now().difference(start);
    final remaining = Duration(hours: _selectedSleepGoal) - elapsed;

    await FastingNotificationService.instance.showSleepOngoingNotification(
      elapsed: elapsed.isNegative ? Duration.zero : elapsed,
      remaining: remaining.isNegative ? Duration.zero : remaining,
      goalHours: _selectedSleepGoal,
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
    final progress = _activeSleepStart == null
        ? 0.0
        : (activeDuration.inMinutes / (_selectedSleepGoal * 60))
            .clamp(0.0, 1.0);

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
                                            '${_selectedSleepGoal}h',
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
                                _dropdownSettingTile<int>(
                                  title: 'Sleep goal',
                                  value: _selectedSleepGoal,
                                  items: _goalOptions,
                                  labelBuilder: (hours) => '$hours hours',
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedSleepGoal = value;
                                    });
                                  },
                                ),
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
                                      : '${(progress * 100).round()}% of your ${_selectedSleepGoal}h goal',
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
                                        color: const Color(0xFFF7F4EE),
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
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF2F3442),
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${DateFormat('MMM d, h:mm a').format(session.start)} to ${DateFormat('h:mm a').format(session.end)}',
                                                  style: const TextStyle(
                                                    color: Colors.black54,
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
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
    return _settingContainer(
      title: title,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.black54,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
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
    final recommendedWake = bedtime.add(Duration(hours: _selectedSleepGoal));
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
