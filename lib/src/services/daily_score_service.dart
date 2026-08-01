class DailyScoreSummary {
  const DailyScoreSummary({
    required this.dailyTrackerScore,
    required this.todoListScore,
    required this.todoListScoreContribution,
    required this.todoListIncludedInTotal,
    required this.totalPoints,
  });

  final int dailyTrackerScore;
  final int todoListScore;
  final int todoListScoreContribution;
  final bool todoListIncludedInTotal;
  final num totalPoints;
}

class DailyScoreService {
  DailyScoreService._();

  static const _defaultActivityIds = {
    'call',
    'steps',
    'exercise',
    'meditation',
    'learning',
    'addValue',
  };

  static int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _isTaskCompleted(
    Map<String, dynamic> tracker,
    String taskId,
  ) {
    if (_defaultActivityIds.contains(taskId)) {
      return tracker[taskId] == true;
    }

    final customDailyTasks = tracker['customDailyTasks'];
    if (customDailyTasks is Map) {
      final customTask = customDailyTasks[taskId];
      if (customTask is Map) return customTask['completed'] == true;
      if (customTask is bool) return customTask;
    }

    return tracker[taskId] == true;
  }

  static int calculateDailyTrackerScore(
    Map<String, dynamic> tracker, {
    required List<String> dailyTrackerIds,
  }) {
    final filteredIds = dailyTrackerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    if (filteredIds.isEmpty) return 0;

    final completedCount =
        filteredIds.where((taskId) => _isTaskCompleted(tracker, taskId)).length;

    return ((completedCount / filteredIds.length) * 100).round().clamp(0, 100);
  }

  static DailyScoreSummary summarizeTracker(
    Map<String, dynamic> tracker, {
    required List<String> dailyTrackerIds,
  }) {
    final dailyTrackerScore = calculateDailyTrackerScore(
      tracker,
      dailyTrackerIds: dailyTrackerIds,
    );
    final todoListScore = _readInt(tracker['todoListScore']).clamp(0, 100);
    final rawTodoListContribution = tracker['todoListScoreDailyContribution'];
    final todoListScoreContribution = rawTodoListContribution is num
        ? rawTodoListContribution.round().clamp(0, 100)
        : todoListScore;
    final effectiveTodoListScore =
        todoListScore > 0 ? todoListScore : todoListScoreContribution;
    final todoListIncludedInTotal =
        tracker['todoListIncludedInTotal'] == true ||
            todoListScore > 0 ||
            todoListScoreContribution > 0;
    final totalPoints = todoListIncludedInTotal
        ? ((dailyTrackerScore + effectiveTodoListScore) / 2).clamp(0, 100)
        : dailyTrackerScore.toDouble();

    return DailyScoreSummary(
      dailyTrackerScore: dailyTrackerScore,
      todoListScore: todoListScore,
      todoListScoreContribution: todoListScoreContribution,
      todoListIncludedInTotal: todoListIncludedInTotal,
      totalPoints: totalPoints,
    );
  }

  static num resolveDisplayTotalPoints(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return 0;

    final rawDailyTrackerScore = data['dailyTrackerScore'];
    final rawTodoListScore = data['todoListScore'];
    final rawTodoListContribution = data['todoListScoreDailyContribution'];
    final includeTodoListScore = data['todoListIncludedInTotal'] == true ||
        _readInt(rawTodoListScore) > 0 ||
        _readInt(rawTodoListContribution) > 0;

    final hasDerivedFields = rawDailyTrackerScore is num ||
        rawTodoListScore is num ||
        rawTodoListContribution is num ||
        data.containsKey('todoListIncludedInTotal');

    if (hasDerivedFields) {
      final dailyTrackerScore = _readInt(rawDailyTrackerScore).clamp(0, 100);
      final todoListScore = _readInt(rawTodoListScore).clamp(0, 100);
      final todoListScoreContribution =
          _readInt(rawTodoListContribution).clamp(0, 100);
      final effectiveTodoListScore =
          todoListScore > 0 ? todoListScore : todoListScoreContribution;
      return includeTodoListScore
          ? ((dailyTrackerScore + effectiveTodoListScore) / 2).clamp(0, 100)
          : dailyTrackerScore;
    }

    final rawTotal =
        data['totalPoints'] ?? data['userTotalScore'] ?? data['score'];
    if (rawTotal is num) return rawTotal.clamp(0, 100);
    return 0;
  }
}
