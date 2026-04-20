import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSleepData();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadSleepData() async {
    final prefs = await SharedPreferences.getInstance();
    final historyStrings = prefs.getStringList(_historyKey) ?? const [];
    final activeStartString = prefs.getString(_activeStartKey);

    setState(() {
      _selectedMode = prefs.getString(_modeKey) ?? _selectedMode;
      _selectedSleepGoal = prefs.getInt(_goalKey) ?? _selectedSleepGoal;
      _selectedBedtime = TimeOfDay(
        hour: prefs.getInt(_bedtimeHourKey) ?? _selectedBedtime.hour,
        minute: prefs.getInt(_bedtimeMinuteKey) ?? _selectedBedtime.minute,
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
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSavingSettings = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _selectedMode);
    await prefs.setInt(_goalKey, _selectedSleepGoal);
    await prefs.setInt(_bedtimeHourKey, _selectedBedtime.hour);
    await prefs.setInt(_bedtimeMinuteKey, _selectedBedtime.minute);

    if (!mounted) return;
    setState(() {
      _isSavingSettings = false;
    });
    _showSnackBar('Sleep settings saved.');
  }

  Future<void> _startSleepSession() async {
    final start = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeStartKey, start.toIso8601String());

    setState(() {
      _activeSleepStart = start;
    });
    _startTicker();
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
    await prefs.remove(_activeStartKey);
    await prefs.setStringList(
      _historyKey,
      updatedHistory.map((item) => item.toJsonString()).toList(),
    );

    _ticker?.cancel();

    setState(() {
      _activeSleepStart = null;
      _history = updatedHistory;
    });

    _showSnackBar(
      'Sleep session saved: ${_formatDuration(session.duration)}.',
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
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
    final theme = Theme.of(context);
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
        : (activeDuration.inMinutes / (_selectedSleepGoal * 60)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F4EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F4EF),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Sleep Tracker'),
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
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE7EDF8),
                        Color(0xFFDDE7F7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sleep Monitoring',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _activeSleepStart == null
                                  ? 'Set your bedtime, start tracking, and build a steadier sleep routine.'
                                  : 'Your sleep session is running. Keep the screen closed and come back when you wake up.',
                              style: const TextStyle(color: Colors.black54),
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
                            child: _settingTile(
                              title: 'Wake notification',
                              value: _selectedMode,
                              trailing: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedMode,
                                  isDense: true,
                                  items: _modeOptions.map((mode) {
                                    return DropdownMenuItem<String>(
                                      value: mode,
                                      child: Text(mode),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedMode = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _settingTile(
                              title: 'Bedtime',
                              value: _selectedBedtime.format(context),
                              trailing: TextButton(
                                onPressed: _pickBedtime,
                                child: const Text('Change'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _settingTile(
                        title: 'Sleep goal',
                        value: '$_selectedSleepGoal hours',
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedSleepGoal,
                            isDense: true,
                            items: _goalOptions.map((hours) {
                              return DropdownMenuItem<int>(
                                value: hours,
                                child: Text('$hours h'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _selectedSleepGoal = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSavingSettings ? null : _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3D4E73),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _isSavingSettings ? 'Saving...' : 'Save settings',
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                borderRadius: BorderRadius.circular(999),
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
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2F3442),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _activeSleepStart == null
                            ? 'Tap Start sleep when you are heading to bed.'
                            : 'Started at ${DateFormat('h:mm a').format(_activeSleepStart!)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: const Color(0xFFEAE6DE),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF788DB7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _activeSleepStart == null
                            ? 'Goal progress will appear while tracking.'
                            : '${(progress * 100).round()}% of your ${_selectedSleepGoal}h goal',
                        style: const TextStyle(
                          color: Colors.black54,
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
                              icon: const Icon(CupertinoIcons.moon_fill),
                              label: const Text('Start sleep'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2F3442),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
                              icon: const Icon(CupertinoIcons.sun_max_fill),
                              label: const Text('End sleep'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2F3442),
                                side: const BorderSide(
                                  color: Color(0xFF2F3442),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
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
                        const Text(
                          'No sleep sessions yet. Start one tonight to build your history.',
                          style: TextStyle(color: Colors.black54),
                        )
                      else
                        ..._history.map((session) {
                          final hitGoal = session.duration.inMinutes >=
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
                                        ? CupertinoIcons.check_mark_circled_solid
                                        : CupertinoIcons.moon_zzz_fill,
                                    color: hitGoal
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFFCC7A00),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDuration(session.duration),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
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
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  Widget _statChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF3D4E73)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
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

  Widget _settingTile({
    required String title,
    required String value,
    required Widget trailing,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ],
      ),
    );
  }

  Widget _sleepInsightRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
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
