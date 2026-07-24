import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class DailyTrackerApiService {
  DailyTrackerApiService._();

  static final DailyTrackerApiService instance = DailyTrackerApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

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
              .map((user) => Map<String, dynamic>.from(user))
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
          .map((friend) => Map<String, dynamic>.from(friend))
          .toList();
    }

    return const [];
  }
}
