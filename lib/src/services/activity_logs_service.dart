import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/calorie_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/fasting_api_service.dart';

enum ActivityLogKind { meditation, steps, exercise, fasting, calories, sleep }

class ActivityLogItem {
  const ActivityLogItem({
    required this.kind,
    required this.title,
    required this.detail,
    required this.value,
    this.timestamp,
  });

  final ActivityLogKind kind;
  final String title;
  final String detail;
  final String value;
  final DateTime? timestamp;
}

class ActivityLogsSnapshot {
  const ActivityLogsSnapshot({
    required this.generatedAt,
    required this.items,
    required this.totalItems,
  });

  final DateTime generatedAt;
  final List<ActivityLogItem> items;
  final int totalItems;

  factory ActivityLogsSnapshot.empty({String? detail}) {
    return ActivityLogsSnapshot(
      generatedAt: DateTime.now(),
      items: detail == null
          ? const <ActivityLogItem>[]
          : [
              ActivityLogItem(
                kind: ActivityLogKind.sleep,
                title: 'No activity logs yet',
                detail: detail,
                value: '--',
              ),
            ],
      totalItems: 0,
    );
  }
}

class ActivityLogsService {
  ActivityLogsService._();

  static final ActivityLogsService instance = ActivityLogsService._();

  String get _todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<ActivityLogsSnapshot> loadToday() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return ActivityLogsSnapshot.empty(
        detail: 'Sign in to see your activity logs.',
      );
    }

    final items = <ActivityLogItem>[];
    final today = _todayKey;

    try {
      final trackerResponse = await DailyTrackerApiService.instance.fetch(
        date: today,
      );
      final tracker = _map(trackerResponse['tracker']);
      final meditationMinutes =
          _intValue(tracker['meditationMinutes'] ?? tracker['meditation_minutes']);
      final stepsTaken =
          _intValue(tracker['stepCount'] ?? tracker['step_count']);

      if (meditationMinutes > 0) {
        items.add(
          ActivityLogItem(
            kind: ActivityLogKind.meditation,
            title: 'Meditation',
            detail: 'Today',
            value: '$meditationMinutes mins',
          ),
        );
      }

      if (stepsTaken > 0) {
        items.add(
          ActivityLogItem(
            kind: ActivityLogKind.steps,
            title: 'Steps',
            detail: 'Today',
            value: NumberFormat.decimalPattern().format(stepsTaken),
          ),
        );
      }

      final calorieResponse = await CalorieTrackerApiService.instance.fetchDay(
        date: today,
      );
      final calorieDay = _map(calorieResponse['day']);
      final totalCalories =
          _intValue(calorieDay['totalCalories'] ?? calorieDay['total_calories']);
      if (totalCalories > 0) {
        items.add(
          ActivityLogItem(
            kind: ActivityLogKind.calories,
            title: 'Calories',
            detail: 'Today',
            value: '$totalCalories kcal',
          ),
        );
      }

      final exerciseLogs = await ExerciseApiService.instance.fetchToday();
      for (final log in exerciseLogs) {
        final type = (log['type']?.toString().trim().isNotEmpty == true)
            ? log['type'].toString().trim()
            : 'Exercise';
        final duration = _durationLabel(
          Duration(
            minutes: _intValue(log['durationMinutes']),
            seconds: _intValue(log['durationSeconds']),
          ),
        );
        final notes = (log['notes'] as String?)?.trim() ?? '';
        items.add(
          ActivityLogItem(
            kind: ActivityLogKind.exercise,
            title: type,
            detail: notes.isEmpty ? 'Logged today' : notes,
            value: duration,
            timestamp: _dateFromValue(log['createdAt'] ?? log['created_at']),
          ),
        );
      }

      final fastingResponse = await FastingApiService.instance.fetchSession();
      final fastingSession = _map(fastingResponse['session']);
      final fastingHistory = fastingResponse['history'] is List
          ? (fastingResponse['history'] as List)
              .whereType<Map>()
              .map((item) => _map(item))
              .toList()
          : <Map<String, dynamic>>[];
      if (fastingSession.isNotEmpty || fastingHistory.isNotEmpty) {
        fastingHistory.sort((a, b) {
          final aEnd = _dateFromValue(a['endTime'] ?? a['end_time']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bEnd = _dateFromValue(b['endTime'] ?? b['end_time']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bEnd.compareTo(aEnd);
        });
        final latestHistory = fastingHistory.isNotEmpty ? fastingHistory.first : {};
        final completedHours = _doubleValue(
          latestHistory['completedHours'] ?? latestHistory['completed_hours'],
        );
        final targetHours = _intValue(
          latestHistory['targetHours'] ?? latestHistory['target_hours'],
        );
        final startTime = _dateFromValue(
          fastingSession['startTime'] ?? fastingSession['start_time'],
        );
        final endTime = _dateFromValue(
          fastingSession['endTime'] ?? fastingSession['end_time'],
        );
        final active = startTime != null && endTime != null;

        if (completedHours > 0 || active) {
          final activeStart = startTime ?? DateTime.now();
          items.add(
            ActivityLogItem(
              kind: ActivityLogKind.fasting,
              title: 'Fasting',
              detail: active ? 'In progress' : 'Completed today',
              value: active
                  ? _durationLabel(DateTime.now().difference(activeStart))
                  : _hoursLabel(completedHours),
            ),
          );
        } else if (targetHours > 0) {
          items.add(
            ActivityLogItem(
              kind: ActivityLogKind.fasting,
              title: 'Fasting',
              detail: 'Goal set',
              value: '${targetHours}h',
            ),
          );
        }
      }

      final sleepItem = await _loadSleepItem();
      if (sleepItem != null) {
        items.add(sleepItem);
      }

      items.sort((a, b) {
        final order = _kindOrder(a.kind).compareTo(_kindOrder(b.kind));
        if (order != 0) return order;
        return (b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0));
      });

      return ActivityLogsSnapshot(
        generatedAt: DateTime.now(),
        items: items,
        totalItems: items.length,
      );
    } catch (_) {
      return ActivityLogsSnapshot.empty(
        detail: 'We could not load every tracker right now.',
      );
    }
  }

  int _kindOrder(ActivityLogKind kind) {
    return switch (kind) {
      ActivityLogKind.meditation => 0,
      ActivityLogKind.steps => 1,
      ActivityLogKind.exercise => 2,
      ActivityLogKind.fasting => 3,
      ActivityLogKind.calories => 4,
      ActivityLogKind.sleep => 5,
    };
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _doubleValue(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _dateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<ActivityLogItem?> _loadSleepItem() async {
    final userId = AuthService.instance.currentSession?.id.toString() ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    final historyKey = 'sleep_tracker_history_$userId';
    final activeKey = 'sleep_tracker_active_start_$userId';
    final activeStart = DateTime.tryParse(prefs.getString(activeKey) ?? '');
    final historyStrings = prefs.getStringList(historyKey) ?? const [];
    final sessions = historyStrings
        .map((entry) {
          try {
            final map = jsonDecode(entry) as Map<String, dynamic>;
            final start = DateTime.tryParse(map['start']?.toString() ?? '');
            final end = DateTime.tryParse(map['end']?.toString() ?? '');
            final goalHours = _intValue(map['goalHours']);
            if (start == null || end == null) return null;
            return _SleepSnapshot(
              start: start,
              end: end,
              goalHours: goalHours,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<_SleepSnapshot>()
        .toList();

    if (activeStart != null) {
      final duration = DateTime.now().difference(activeStart);
      if (duration.inMinutes <= 0) return null;
      return ActivityLogItem(
        kind: ActivityLogKind.sleep,
        title: 'Sleep',
        detail: 'In progress',
        value: _durationLabel(duration),
        timestamp: activeStart,
      );
    }

    if (sessions.isEmpty) return null;
    final latest = sessions.first;
    return ActivityLogItem(
      kind: ActivityLogKind.sleep,
      title: 'Sleep',
      detail: latest.duration.inHours >= latest.goalHours
          ? 'Goal hit'
          : 'Completed',
      value: _durationLabel(latest.duration),
      timestamp: latest.end,
    );
  }

  String _durationLabel(Duration duration) {
    if (duration.inHours >= 1 && duration.inMinutes % 60 == 0) {
      return '${duration.inHours}h';
    }
    if (duration.inHours >= 1) {
      final remainingMinutes = duration.inMinutes % 60;
      return '${duration.inHours}h ${remainingMinutes}m';
    }
    if (duration.inMinutes >= 1) {
      return '${duration.inMinutes} mins';
    }
    return '${duration.inSeconds}s';
  }

  String _hoursLabel(double hours) {
    final label = hours == hours.truncateToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return '${label}h';
  }
}

class _SleepSnapshot {
  const _SleepSnapshot({
    required this.start,
    required this.end,
    required this.goalHours,
  });

  final DateTime start;
  final DateTime end;
  final int goalHours;

  Duration get duration => end.difference(start);
}
