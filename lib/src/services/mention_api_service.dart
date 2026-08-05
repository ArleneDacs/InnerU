import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class MentionCandidate {
  const MentionCandidate(
      {required this.id, required this.name, this.profilePic});

  factory MentionCandidate.fromJson(Map<String, dynamic> json) {
    return MentionCandidate(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      profilePic: json['profilePic'] as String?,
    );
  }

  final String id;
  final String name;
  final String? profilePic;
}

class MentionApiService {
  MentionApiService._();

  static final MentionApiService instance = MentionApiService._();
  final ApiClient _api = ApiClient.instance;

  Future<List<MentionCandidate>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final session = AuthService.instance.currentSession;
    if (session == null) return const [];

    final response = await _api.getJson(
      '/api/community/mentionable-users?q=${Uri.encodeQueryComponent(trimmed)}',
      token: session.token,
    );
    // The backend returns a bare JSON array (response()->json([...])) for
    // this endpoint. ApiClient._decodeResponse always returns a
    // Map<String, dynamic>, and wraps any top-level non-Map decoded JSON
    // (including a bare array) as {'data': data} -- so `response['data']`
    // is the actual list here, not a fallback guess.
    final list = response['data'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MentionCandidate.fromJson)
        .toList();
  }
}
