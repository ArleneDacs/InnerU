import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class UserService {
  static final _api = ApiClient.instance;

  static Future<Map<String, dynamic>> getUserData() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return {};

    final response = await _api.getJson(
      '/api/me',
      token: session.token,
    );
    final user = response['user'];
    if (user is! Map<String, dynamic>) {
      return {};
    }

    return _normalizeUserMap(user);
  }

  static Future<Map<String, dynamic>> updateUserData({
    String? name,
    String? email,
    String? number,
    String? birthdate,
  }) async {
    return updateUserFields({
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (number != null) 'number': number,
      if (birthdate != null) 'birthdate': birthdate,
    });
  }

  static Future<Map<String, dynamic>> updateUserFields(
    Map<String, dynamic> payload,
  ) async {
    final session = AuthService.instance.currentSession;
    if (session == null || payload.isEmpty) return {};

    final response = await _api.patchJson(
      '/api/me',
      payload,
      token: session.token,
    );
    final user = response['user'];
    if (user is! Map<String, dynamic>) {
      return {};
    }

    return _normalizeUserMap(user);
  }

  static Map<String, dynamic> _normalizeUserMap(Map<String, dynamic> user) {
    return {
      ...user,
      'username': user['name']?.toString() ?? user['username']?.toString(),
      'profilePic': user['profile_pic']?.toString() ?? user['profilePic'],
      'profile_pic': user['profile_pic']?.toString(),
      'birthdate': user['birthdate']?.toString(),
      'number': user['number']?.toString(),
      'email': user['email']?.toString(),
    };
  }
}
