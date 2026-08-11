import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';

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
    // Keep all client callers inside the API's seconds contract. The tracker
    // already bounds elapsed time, but this final guard prevents a stale or
    // future caller from creating an unsaveable request with conflicting
    // minutes/seconds values.
    final requestedDuration = durationSeconds > 0
        ? Duration(seconds: durationSeconds)
        : Duration(minutes: durationMinutes);
    final safeDuration = boundedExerciseLogDuration(requestedDuration);
    return _api.postJson(
      '/api/exercise',
      {
        'type': type,
        'duration_minutes': exerciseLogDurationMinutes(safeDuration),
        'duration_seconds': safeDuration.inSeconds,
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
