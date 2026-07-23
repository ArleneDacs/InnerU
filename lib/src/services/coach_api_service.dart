import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CoachApiService {
  CoachApiService._();

  static final CoachApiService instance = CoachApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Stream<T> _poll<T>(
    Future<T> Function() fetch, {
    required T fallback,
    Duration interval = const Duration(seconds: 3),
  }) async* {
    while (true) {
      try {
        yield await fetch();
      } catch (_) {
        yield fallback;
      }
      await Future.delayed(interval);
    }
  }

  Future<String> createGroup({
    required String name,
  }) async {
    final response = await _api.postJson(
      '/api/coach/groups',
      {'name': name},
      token: _token,
    );

    final group = response['group'];
    if (group is Map<String, dynamic>) {
      return group['id']?.toString() ?? '';
    }
    return '';
  }

  Future<void> deleteGroup(String groupId) async {
    await _api.deleteJson(
      '/api/coach/groups/$groupId',
      token: _token,
    );
  }

  Future<void> assignMentee({
    required String menteeId,
    required String teamName,
    String? menteeName,
    String? menteeEmail,
    String? groupId,
    String? groupName,
  }) async {
    await _api.postJson(
      '/api/coach/mentees/assign',
      {
        'mentee_id': menteeId,
        'mentee_name': menteeName,
        'mentee_email': menteeEmail,
        'team_name': teamName,
        'group_id': groupId,
        'group_name': groupName,
      },
      token: _token,
    );
  }

  Future<void> removeMentee(String menteeId) async {
    await _api.deleteJson(
      '/api/coach/mentees/$menteeId',
      token: _token,
    );
  }

  Future<void> acceptRequest({
    required String requestId,
    required String teamName,
    String? groupId,
    String? groupName,
  }) async {
    await _api.patchJson(
      '/api/coach/requests/$requestId/accept',
      {
        'team_name': teamName,
        'group_id': groupId,
        'group_name': groupName,
      },
      token: _token,
    );
  }

  Future<void> declineRequest(String requestId) async {
    await _api.patchJson(
      '/api/coach/requests/$requestId/decline',
      const <String, dynamic>{},
      token: _token,
    );
  }

  Future<void> createRequest({
    required String coachId,
    required String coachName,
    String? coachEmail,
    String? applicantRole,
    bool applicantIsCoach = false,
    String applyingAs = 'mentee',
    String status = 'pending',
    String? groupId,
    String? groupName,
    String? menteeName,
    String? menteeEmail,
  }) async {
    await _api.postJson(
      '/api/coach/requests',
      {
        'coach_id': coachId,
        'coach_name': coachName,
        'coach_email': coachEmail,
        'applicant_role': applicantRole,
        'applicant_is_coach': applicantIsCoach,
        'applying_as': applyingAs,
        'status': status,
        'group_id': groupId,
        'group_name': groupName,
        'mentee_name': menteeName,
        'mentee_email': menteeEmail,
      },
      token: _token,
    );
  }

  Future<List<Map<String, dynamic>>> fetchRequests() async {
    final response = await _api.getJson(
      '/api/coach/requests',
      token: _token,
    );
    final requests = response['requests'];
    if (requests is! List) {
      return const <Map<String, dynamic>>[];
    }

    return requests
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchCoaches() async {
    final response = await _api.getJson(
      '/api/coaches',
      token: _token,
    );
    final coaches = response['coaches'];
    if (coaches is! List) {
      return const <Map<String, dynamic>>[];
    }

    return coaches
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchGroups() async {
    final response = await _api.getJson(
      '/api/coach/groups',
      token: _token,
    );
    final groups = response['groups'];
    if (groups is! List) {
      return const <Map<String, dynamic>>[];
    }

    return groups
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> updateGroupCoaches({
    required String groupId,
    required List<String> coachIds,
  }) async {
    await _api.patchJson(
      '/api/coach/groups/$groupId/coaches',
      {
        'coach_ids': coachIds,
      },
      token: _token,
    );
  }

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final response = await _api.getJson(
      '/api/coach/users',
      token: _token,
    );
    final users = response['users'];
    if (users is! List) {
      return const <Map<String, dynamic>>[];
    }

    return users
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchMentees() async {
    final response = await _api.getJson(
      '/api/coach/mentees',
      token: _token,
    );
    final mentees = response['mentees'];
    if (mentees is! List) {
      return const <Map<String, dynamic>>[];
    }

    return mentees
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>?> fetchLatestTracker(String menteeId) async {
    final response = await _api.getJson(
      '/api/coach/mentees/$menteeId/latest-tracker',
      token: _token,
    );
    final tracker = response['tracker'];
    if (tracker is Map<String, dynamic>) {
      return tracker;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchMenteeTrackers(
    String menteeId, {
    String? month,
  }) async {
    final path = month == null || month.isEmpty
        ? '/api/coach/mentees/$menteeId/trackers'
        : '/api/coach/mentees/$menteeId/trackers?month=$month';
    final response = await _api.getJson(
      path,
      token: _token,
    );
    final trackers = response['trackers'];
    if (trackers is! List) {
      return const <Map<String, dynamic>>[];
    }

    return trackers
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> fetchLeaderboard() async {
    return _api.getJson(
      '/api/leaderboard',
      token: _token,
    );
  }

  Stream<List<Map<String, dynamic>>> watchRequests() => _poll(
        fetchRequests,
        fallback: const <Map<String, dynamic>>[],
      );

  Stream<List<Map<String, dynamic>>> watchGroups() => _poll(
        fetchGroups,
        fallback: const <Map<String, dynamic>>[],
      );

  Stream<List<Map<String, dynamic>>> watchMentees() => _poll(
        fetchMentees,
        fallback: const <Map<String, dynamic>>[],
      );
}
