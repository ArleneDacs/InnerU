import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class DailyCheckInApiService {
  DailyCheckInApiService._();

  static final DailyCheckInApiService instance = DailyCheckInApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<Map<String, dynamic>> fetch({String? date}) async {
    final query = <String, String>{};
    if (date != null && date.isNotEmpty) {
      query['date'] = date;
    }

    final path = query.isEmpty
        ? '/api/daily-check-ins'
        : Uri(path: '/api/daily-check-ins', queryParameters: query).toString();

    return _api.getJson(path, token: _token);
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? month}) async {
    final query = <String, String>{};
    if (month != null && month.isNotEmpty) {
      query['month'] = month;
    }

    final path = query.isEmpty
        ? '/api/daily-check-ins/history'
        : Uri(path: '/api/daily-check-ins/history', queryParameters: query)
            .toString();

    final response = await _api.getJson(path, token: _token);
    final checkIns = response['checkIns'];
    if (checkIns is List) {
      return checkIns
          .whereType<Map>()
          .map((checkIn) => Map<String, dynamic>.from(checkIn))
          .toList();
    }

    return const [];
  }

  Future<Map<String, dynamic>> upsert({
    String? date,
    required int rating,
    String? winsToday,
    String? challenges,
    String? lessonsLearned,
    String? gratitude,
    String? tomorrowFocus,
    String? username,
    String? lastFiledAt,
  }) async {
    final payload = <String, dynamic>{
      if (date != null) 'date': date,
      'rating': rating,
      if (winsToday != null) 'wins_today': winsToday,
      if (challenges != null) 'challenges': challenges,
      if (lessonsLearned != null) 'lessons_learned': lessonsLearned,
      if (gratitude != null) 'gratitude': gratitude,
      if (tomorrowFocus != null) 'tomorrow_focus': tomorrowFocus,
      if (username != null) 'username': username,
      if (lastFiledAt != null) 'last_filed_at': lastFiledAt,
    };

    return _api.postJson('/api/daily-check-ins', payload, token: _token);
  }
}
