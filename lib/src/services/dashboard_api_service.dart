import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class DashboardApiService {
  DashboardApiService._();

  static final DashboardApiService instance = DashboardApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Future<Map<String, dynamic>> fetchDashboard() async {
    return _api.getJson('/api/dashboard', token: _token);
  }
}
