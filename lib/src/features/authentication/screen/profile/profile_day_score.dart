class DailyTrackerHistoryTask {
  const DailyTrackerHistoryTask({
    required this.title,
    required this.completed,
  });

  final String title;
  final bool completed;
}

const List<String> _dailyTrackerTaskOrder = [
  'call',
  'steps',
  'exercise',
  'meditation',
  'learning',
  'addValue',
];

String _titleForTaskKey(String key) {
  switch (key) {
    case 'call':
      return 'Call';
    case 'steps':
      return 'Steps';
    case 'exercise':
      return 'Exercise';
    case 'meditation':
      return 'Meditation';
    case 'learning':
      return 'Learning';
    case 'addValue':
      return 'Add Value';
    default:
      return key;
  }
}

int? _readIntField(
  Map<String, dynamic> trackerData,
  List<String> keys,
) {
  for (final key in keys) {
    final raw = trackerData[key];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

Map<String, dynamic>? _readTaskMap(
  Map<String, dynamic> trackerData,
) {
  final raw = trackerData['customDailyTasks'] ?? trackerData['custom_daily_tasks'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}

/// Historical daily-tracker tasks for a single saved record.
///
/// This intentionally reads the tasks from the record itself so that editing
/// today's tracker does not change how earlier days are rendered.
List<DailyTrackerHistoryTask> resolveDayTrackerTasks(
  Map<String, dynamic> trackerData,
) {
  final tasks = <DailyTrackerHistoryTask>[];

  for (final key in _dailyTrackerTaskOrder) {
    tasks.add(
      DailyTrackerHistoryTask(
        title: _titleForTaskKey(key),
        completed: trackerData[key] == true,
      ),
    );
  }

  final customTasks = _readTaskMap(trackerData);
  if (customTasks != null) {
    for (final entry in customTasks.entries) {
      final value = entry.value;
      if (value is Map) {
        final title = value['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        tasks.add(
          DailyTrackerHistoryTask(
            title: title,
            completed: value['completed'] == true,
          ),
        );
      } else if (value is bool) {
        final title = entry.key.toString().trim();
        if (title.isEmpty) continue;
        tasks.add(
          DailyTrackerHistoryTask(
            title: title,
            completed: value,
          ),
        );
      }
    }
  }

  return tasks;
}

/// The score percentage (0-100) for a single day's daily-tracker record.
///
/// The preferred value is the record's own `dailyTrackerScore` if present.
/// Otherwise we derive a pure daily-tracker completion score from the saved
/// task snapshot, excluding todo-list blending so a fully completed day shows
/// 100%.
int resolveDayScorePercent(Map<String, dynamic> trackerData) {
  final directScore = _readIntField(
    trackerData,
    const ['dailyTrackerScore', 'daily_tracker_score'],
  );
  if (directScore != null) {
    return directScore.clamp(0, 100);
  }

  final tasks = resolveDayTrackerTasks(trackerData);
  if (tasks.isNotEmpty) {
    final completedCount = tasks.where((task) => task.completed).length;
    return ((completedCount / tasks.length) * 100).round().clamp(0, 100);
  }

  final fallbackScore = _readIntField(
    trackerData,
    const ['userTotalScore', 'user_total_score'],
  );
  return fallbackScore?.clamp(0, 100) ?? 0;
}
