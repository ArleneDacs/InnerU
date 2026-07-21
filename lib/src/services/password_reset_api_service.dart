import 'package:selfcare_projects/src/services/api_client.dart';

class PasswordResetApiService {
  PasswordResetApiService._();

  static final PasswordResetApiService instance = PasswordResetApiService._();

  final ApiClient _api = ApiClient.instance;

  Future<Map<String, dynamic>> sendResetLink(String email) async {
    return _api.postJson(
      '/api/auth/password/forgot',
      {'email': email.trim()},
    );
  }

  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String email,
    required String password,
  }) async {
    return _api.postJson(
      '/api/auth/password/reset',
      {
        'token': token.trim(),
        'email': email.trim(),
        'password': password,
        'password_confirmation': password,
      },
    );
  }
}
