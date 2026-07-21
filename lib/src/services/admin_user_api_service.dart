import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class AdminUserApiUser {
  const AdminUserApiUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isCoach,
    required this.isAdmin,
    this.number,
    this.companyName,
    this.companyCode,
    this.profilePic,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final bool isCoach;
  final bool isAdmin;
  final String? number;
  final String? companyName;
  final String? companyCode;
  final String? profilePic;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminUserApiUser.fromJson(Map<String, dynamic> json) {
    return AdminUserApiUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'user',
      isCoach: json['isCoach'] == true,
      isAdmin: json['isAdmin'] == true,
      number: json['number']?.toString(),
      companyName: json['companyName']?.toString(),
      companyCode: json['companyCode']?.toString(),
      profilePic: json['profilePic']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class AdminUserApiService {
  AdminUserApiService._();

  static final AdminUserApiService instance = AdminUserApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<AdminUserApiUser>> fetchUsers() async {
    final response = await _api.getJson(
      '/api/admin/users',
      token: _token,
    );
    final users = response['users'];
    if (users is! List) return const <AdminUserApiUser>[];

    return users
        .whereType<Map>()
        .map((item) => AdminUserApiUser.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  Future<AdminUserApiUser> updateRole({
    required String userId,
    required String role,
    String? name,
    String? number,
  }) async {
    final response = await _api.patchJson(
      '/api/admin/users/$userId/role',
      {
        'role': role,
        if (name != null) 'name': name,
        if (number != null) 'number': number,
      },
      token: _token,
    );
    final user = response['user'];
    if (user is Map<String, dynamic>) {
      return AdminUserApiUser.fromJson(user);
    }
    return AdminUserApiUser.fromJson(<String, dynamic>{});
  }
}
