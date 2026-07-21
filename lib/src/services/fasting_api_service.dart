import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class FastingApiService {
  FastingApiService._();

  static final FastingApiService instance = FastingApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<Map<String, dynamic>> fetchSession() async {
    return _api.getJson('/api/fasting', token: _token);
  }

  Future<List<Map<String, dynamic>>> fetchHistory({int? limit}) async {
    final query = <String, String>{};
    if (limit != null) {
      query['limit'] = limit.toString();
    }

    final path = query.isEmpty
        ? '/api/fasting/history'
        : Uri(path: '/api/fasting/history', queryParameters: query).toString();
    final response = await _api.getJson(path, token: _token);
    final history = response['history'];
    if (history is List) {
      return history
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> start({required int targetHours}) async {
    return _api.postJson(
      '/api/fasting/start',
      {'target_hours': targetHours},
      token: _token,
    );
  }

  Future<Map<String, dynamic>> end() async {
    return _api.postJson('/api/fasting/end', const {}, token: _token);
  }
}
