import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CoachDirectoryApiCoach {
  const CoachDirectoryApiCoach({
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

  factory CoachDirectoryApiCoach.fromJson(Map<String, dynamic> json) {
    return CoachDirectoryApiCoach(
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
    );
  }
}

class CoachDirectoryApiService {
  CoachDirectoryApiService._();

  static final CoachDirectoryApiService instance = CoachDirectoryApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<CoachDirectoryApiCoach>> fetchCoaches() async {
    final response = await _api.getJson(
      '/api/coaches',
      token: _token,
    );
    final coaches = response['coaches'];
    if (coaches is! List) {
      return const <CoachDirectoryApiCoach>[];
    }

    return coaches
        .whereType<Map>()
        .map((item) => CoachDirectoryApiCoach.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }
}
