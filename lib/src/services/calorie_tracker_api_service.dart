import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CalorieTrackerApiService {
  CalorieTrackerApiService._();

  static final CalorieTrackerApiService instance =
      CalorieTrackerApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<Map<String, dynamic>> fetchDay({String? date}) async {
    final query = <String, String>{};
    if (date != null && date.isNotEmpty) {
      query['date'] = date;
    }

    final path = query.isEmpty
        ? '/api/calorie'
        : Uri(path: '/api/calorie', queryParameters: query).toString();
    return _api.getJson(path, token: _token);
  }

  Future<List<Map<String, dynamic>>> fetchHistory({int? limit}) async {
    final query = <String, String>{};
    if (limit != null) {
      query['limit'] = limit.toString();
    }

    final path = query.isEmpty
        ? '/api/calorie/history'
        : Uri(path: '/api/calorie/history', queryParameters: query).toString();
    final response = await _api.getJson(path, token: _token);
    final days = response['days'];
    if (days is List) {
      return days
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> updateDay({
    required String date,
    int? dailyGoal,
    int? waterGlasses,
    int? waterGoal,
  }) async {
    final payload = <String, dynamic>{
      'date': date,
      if (dailyGoal != null) 'daily_goal': dailyGoal,
      if (waterGlasses != null) 'water_glasses': waterGlasses,
      if (waterGoal != null) 'water_goal': waterGoal,
    };

    return _api.postJson('/api/calorie/day', payload, token: _token);
  }

  Future<Map<String, dynamic>> addEntry({
    required String date,
    required String meal,
    required String mealType,
    required int calories,
    int protein = 0,
    int carbs = 0,
    int fat = 0,
    double? quantity,
    String? measurementUnit,
    String? photoUrl,
  }) async {
    final payload = <String, dynamic>{
      'date': date,
      'meal': meal,
      'meal_type': mealType,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      if (quantity != null) 'quantity': quantity,
      if (measurementUnit != null) 'measurement_unit': measurementUnit,
      if (photoUrl != null) 'photo_url': photoUrl,
    };

    return _api.postJson('/api/calorie/entries', payload, token: _token);
  }

  Future<Map<String, dynamic>?> lookupFoodMemory(String key) async {
    if (key.trim().isEmpty) return null;

    final response = await _api.getJson(
      '/api/calorie/food-memory/$key',
      token: _token,
    );
    final memory = response['memory'];
    if (memory is Map) {
      return memory.cast<String, dynamic>();
    }
    return null;
  }

  Future<Map<String, dynamic>> upsertFoodMemory({
    required String key,
    required String displayName,
    required String lookupName,
    required int calories,
    int protein = 0,
    int carbs = 0,
    int fat = 0,
    String source = 'manual',
  }) async {
    return _api.postJson(
      '/api/calorie/food-memory',
      {
        'key': key,
        'display_name': displayName,
        'lookup_name': lookupName,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'source': source,
      },
      token: _token,
    );
  }
}
