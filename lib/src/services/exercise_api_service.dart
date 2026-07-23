import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class ExerciseApiService {
  ExerciseApiService._();

  static final ExerciseApiService instance = ExerciseApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<Map<String, dynamic>>> fetchToday() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final response = await _api.getJson(
      '/api/exercise?date=$today',
      token: _token,
    );
    final logs = response['logs'];
    if (logs is List) {
      return logs
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> store({
    required String type,
    required int durationMinutes,
    required int durationSeconds,
    required int intensity,
    String? notes,
    String? startPhotoUrl,
    String? endPhotoUrl,
    String? date,
  }) async {
    return _api.postJson(
      '/api/exercise',
      {
        'type': type,
        'duration_minutes': durationMinutes,
        'duration_seconds': durationSeconds,
        'intensity': intensity,
        if (notes != null) 'notes': notes,
        if (startPhotoUrl != null) 'start_photo_url': startPhotoUrl,
        if (endPhotoUrl != null) 'end_photo_url': endPhotoUrl,
        if (date != null) 'date': date,
      },
      token: _token,
    );
  }

  Future<Map<String, dynamic>> delete(String logId) async {
    return _api.deleteJson('/api/exercise/$logId', token: _token);
  }
}
