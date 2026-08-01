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
  final raw =
      trackerData['customDailyTasks'] ?? trackerData['custom_daily_tasks'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return null;
}

List<String> _readSnapshotTaskIds(Map<String, dynamic> trackerData) {
  final taskMap = _readTaskMap(trackerData);
  final raw = taskMap?['__snapshotTaskIds'];
  if (raw is! List) return const [];

  return raw
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

bool _hasTaskField(
  Map<String, dynamic> trackerData,
  String camelCaseKey,
) {
  final snakeCaseKey = camelCaseKey.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => '_${match.group(1)!.toLowerCase()}',
  );
  return trackerData.containsKey(camelCaseKey) ||
      trackerData.containsKey(snakeCaseKey);
}

bool _readBoolField(
  Map<String, dynamic> trackerData,
  String camelCaseKey,
) {
  final snakeCaseKey = camelCaseKey.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => '_${match.group(1)!.toLowerCase()}',
  );
  final raw = trackerData.containsKey(camelCaseKey)
      ? trackerData[camelCaseKey]
      : trackerData[snakeCaseKey];
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

/// Historical daily-tracker tasks for a single saved record.
///
/// This intentionally reads the tasks from the record itself so that editing
/// today's tracker does not change how earlier days are rendered. Only task
/// fields that were actually present in that saved record are included.
List<DailyTrackerHistoryTask> resolveDayTrackerTasks(
  Map<String, dynamic> trackerData,
) {
  final tasks = <DailyTrackerHistoryTask>[];
  final snapshotTaskIds = _readSnapshotTaskIds(trackerData);
  final taskMap = _readTaskMap(trackerData);

  if (snapshotTaskIds.isNotEmpty) {
    for (final key in snapshotTaskIds) {
      final customTask = taskMap?[key];
      if (_dailyTrackerTaskOrder.contains(key) &&
          _hasTaskField(trackerData, key)) {
        final snapshotTitle = customTask is Map
            ? customTask['title']?.toString().trim() ?? ''
            : '';
        tasks.add(
          DailyTrackerHistoryTask(
            title:
                snapshotTitle.isEmpty ? _titleForTaskKey(key) : snapshotTitle,
            completed: _readBoolField(trackerData, key),
          ),
        );
        continue;
      }

      if (customTask is Map) {
        final title = customTask['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        tasks.add(
          DailyTrackerHistoryTask(
            title: title,
            completed: customTask['completed'] == true,
          ),
        );
        continue;
      }

      if (customTask is bool) {
        tasks.add(
          DailyTrackerHistoryTask(
            title: _titleForTaskKey(key),
            completed: customTask,
          ),
        );
        continue;
      }

      if (_hasTaskField(trackerData, key)) {
        tasks.add(
          DailyTrackerHistoryTask(
            title: _titleForTaskKey(key),
            completed: _readBoolField(trackerData, key),
          ),
        );
      }
    }

    return tasks;
  }

  for (final key in _dailyTrackerTaskOrder) {
    if (!_hasTaskField(trackerData, key)) continue;
    tasks.add(
      DailyTrackerHistoryTask(
        title: _titleForTaskKey(key),
        completed: _readBoolField(trackerData, key),
      ),
    );
  }

  final customTasks = taskMap;
  if (customTasks != null) {
    for (final entry in customTasks.entries) {
      if (entry.key.toString() == '__snapshotTaskIds') {
        continue;
      }
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
