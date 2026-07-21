import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class AdminAccess {
  static bool hasAdminRole(Map<String, dynamic>? data) {
    final role = (data?['role'] as String?)?.trim().toLowerCase();
    return role == 'admin' || data?['isAdmin'] == true;
  }

  static Future<bool> isAdmin([Object? user]) async {
    final session = AuthService.instance.currentSession;
    if (session == null) return false;
    final userData = await UserService.getUserData();
    return hasAdminRole(userData);
  }
}
