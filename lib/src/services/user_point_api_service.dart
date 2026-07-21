import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class UserPointApiService {
  UserPointApiService._();

  static final UserPointApiService instance = UserPointApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<Map<String, dynamic>> upsert({
    required String date,
    String? username,
    num? totalPoints,
    int? activityPoints,
    int? dailyTrackerScore,
    int? todoListScore,
    int? todoListScoreDailyContribution,
    bool? todoListIncludedInTotal,
    int? userTotalScore,
    Map<String, dynamic>? taskPoints,
    Map<String, dynamic>? tasks,
    String? server,
    String? companyId,
    String? companyCode,
    String? companyName,
    Map<String, dynamic>? activityCounts,
  }) async {
    final payload = <String, dynamic>{
      'date': date,
      if (username != null) 'username': username,
      if (totalPoints != null) 'total_points': totalPoints,
      if (activityPoints != null) 'activity_points': activityPoints,
      if (dailyTrackerScore != null) 'daily_tracker_score': dailyTrackerScore,
      if (todoListScore != null) 'todo_list_score': todoListScore,
      if (todoListScoreDailyContribution != null)
        'todo_list_score_daily_contribution': todoListScoreDailyContribution,
      if (todoListIncludedInTotal != null)
        'todo_list_included_in_total': todoListIncludedInTotal,
      if (userTotalScore != null) 'user_total_score': userTotalScore,
      if (taskPoints != null) 'task_points': taskPoints,
      if (tasks != null) 'tasks': tasks,
      if (server != null) 'server': server,
      if (companyId != null) 'company_id': companyId,
      if (companyCode != null) 'company_code': companyCode,
      if (companyName != null) 'company_name': companyName,
      if (activityCounts != null) 'activity_counts': activityCounts,
    };

    return _api.postJson('/api/user-points', payload, token: _token);
  }
}
