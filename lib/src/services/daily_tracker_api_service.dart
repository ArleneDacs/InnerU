import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class DailyTrackerApiService {
  DailyTrackerApiService._();

  static final DailyTrackerApiService instance = DailyTrackerApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is bool) return value ? 1 : 0;
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static Map<String, bool> _normalizeTaskMap(dynamic rawTasks) {
    if (rawTasks is! Map) {
      return const <String, bool>{};
    }

    final tasks = Map<String, dynamic>.from(rawTasks);
    return {
      'Call': _asBool(tasks['Call'] ?? tasks['call']),
      'Steps': _asBool(tasks['Steps'] ?? tasks['steps']),
      'Exercise': _asBool(tasks['Exercise'] ?? tasks['exercise']),
      'Meditation': _asBool(tasks['Meditation'] ?? tasks['meditation']),
      'Learning': _asBool(tasks['Learning'] ?? tasks['learning']),
      'Add Value': _asBool(tasks['Add Value'] ?? tasks['addValue'] ?? tasks['add_value']),
    };
  }

  static Map<String, dynamic> _normalizeAdminUser(Map<String, dynamic> user) {
    final progress = user['progress'];
    final normalizedProgress = <String, Map<String, bool>>{};
    if (progress is Map) {
      for (final entry in progress.entries) {
        final dateKey = entry.key.toString();
        normalizedProgress[dateKey] = _normalizeTaskMap(entry.value);
      }
    }

    return {
      ...user,
      'todayCompletedCount': _asInt(user['todayCompletedCount']),
      'todayTaskCount': _asInt(user['todayTaskCount'], fallback: 6),
      'todayUpdatedAt': user['todayUpdatedAt']?.toString() ?? '',
      'progress': normalizedProgress,
    };
  }

  static Map<String, dynamic> _normalizeFriend(Map<String, dynamic> friend) {
    final progress = friend['progress'];
    final normalizedProgress = <String, Map<String, bool>>{};
    if (progress is Map) {
      for (final entry in progress.entries) {
        final dateKey = entry.key.toString();
        normalizedProgress[dateKey] = _normalizeTaskMap(entry.value);
      }
    }

    return {
      ...friend,
      'progress': normalizedProgress,
    };
  }

  Future<Map<String, dynamic>> upsert({
    String? date,
    int? stepCount,
    int? stepGoal,
    bool? meditation,
    bool? steps,
    bool? call,
    bool? exercise,
    bool? learning,
    bool? addValue,
    bool? todoList,
    int? callCount,
    int? exerciseCount,
    int? exerciseMinutes,
    int? learningCount,
    int? valueCount,
    int? todoListCount,
    int? todoListScore,
    int? todoListScoreDailyContribution,
    bool? todoListIncludedInTotal,
    int? userTotalScore,
    Map<String, dynamic>? customDailyTasks,
    int? meditationMinutes,
    String? username,
    String? companyId,
    String? companyCode,
    String? companyName,
  }) async {
    final payload = <String, dynamic>{
      if (date != null) 'date': date,
      if (stepCount != null) 'step_count': stepCount,
      if (stepGoal != null) 'step_goal': stepGoal,
      if (meditation != null) 'meditation': meditation,
      if (steps != null) 'steps': steps,
      if (call != null) 'call': call,
      if (exercise != null) 'exercise': exercise,
      if (learning != null) 'learning': learning,
      if (addValue != null) 'add_value': addValue,
      if (todoList != null) 'todo_list': todoList,
      if (callCount != null) 'call_count': callCount,
      if (exerciseCount != null) 'exercise_count': exerciseCount,
      if (exerciseMinutes != null) 'exercise_minutes': exerciseMinutes,
      if (learningCount != null) 'learning_count': learningCount,
      if (valueCount != null) 'value_count': valueCount,
      if (todoListCount != null) 'todo_list_count': todoListCount,
      if (todoListScore != null) 'todo_list_score': todoListScore,
      if (todoListScoreDailyContribution != null)
        'todo_list_score_daily_contribution':
            todoListScoreDailyContribution,
      if (todoListIncludedInTotal != null)
        'todo_list_included_in_total': todoListIncludedInTotal,
      if (userTotalScore != null) 'user_total_score': userTotalScore,
      if (customDailyTasks != null) 'custom_daily_tasks': customDailyTasks,
      if (meditationMinutes != null) 'meditation_minutes': meditationMinutes,
      if (username != null) 'username': username,
      if (companyId != null) 'company_id': companyId,
      if (companyCode != null) 'company_code': companyCode,
      if (companyName != null) 'company_name': companyName,
    };

    return _api.postJson('/api/daily-tracker', payload, token: _token);
  }

  Future<Map<String, dynamic>> fetch({String? date}) async {
    final query = <String, String>{};
    if (date != null && date.isNotEmpty) {
      query['date'] = date;
    }

    final path = query.isEmpty
        ? '/api/daily-tracker'
        : Uri(path: '/api/daily-tracker', queryParameters: query).toString();

    return _api.getJson(path, token: _token);
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? month}) async {
    final query = <String, String>{};
    if (month != null && month.isNotEmpty) {
      query['month'] = month;
    }

    final path = query.isEmpty
        ? '/api/daily-tracker/history'
        : Uri(path: '/api/daily-tracker/history', queryParameters: query)
            .toString();

    final response = await _api.getJson(path, token: _token);
    final trackers = response['trackers'];
    if (trackers is List) {
      return trackers
          .whereType<Map>()
          .map((tracker) => Map<String, dynamic>.from(tracker))
          .toList();
    }

    return const [];
  }

  Future<Map<String, dynamic>> fetchAdminOverview({String? month}) async {
    final query = <String, String>{};
    if (month != null && month.isNotEmpty) {
      query['month'] = month;
    }

    final path = query.isEmpty
        ? '/api/admin/daily-tracker'
        : Uri(path: '/api/admin/daily-tracker', queryParameters: query)
            .toString();

    final response = await _api.getJson(path, token: _token);
    final users = response['users'];
    return {
      'month': response['month']?.toString() ?? month ?? '',
      'date': response['date']?.toString() ?? '',
      'users': users is List
          ? users
              .whereType<Map>()
              .map(
                (user) => _normalizeAdminUser(Map<String, dynamic>.from(user)),
              )
              .toList()
          : const <Map<String, dynamic>>[],
    };
  }

  Future<List<Map<String, dynamic>>> fetchFriends({String? month}) async {
    final query = <String, String>{};
    if (month != null && month.isNotEmpty) {
      query['month'] = month;
    }

    final path = query.isEmpty
        ? '/api/daily-tracker/friends'
        : Uri(path: '/api/daily-tracker/friends', queryParameters: query)
            .toString();

    final response = await _api.getJson(path, token: _token);
    final friends = response['friends'];
    if (friends is List) {
      return friends
          .whereType<Map>()
          .map((friend) => _normalizeFriend(Map<String, dynamic>.from(friend)))
          .toList();
    }

    return const [];
  }
}
