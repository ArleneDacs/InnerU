import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class StepMapApiService {
  StepMapApiService._();

  static final StepMapApiService instance = StepMapApiService._();

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

  Future<List<Map<String, dynamic>>> fetchSessions(String userId) async {
    final response = await _api.getJson('/api/walk-sessions?userId=$userId', token: _token);
    final raw = response['sessions'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchMembers(String sessionId) async {
    final response = await _api.getJson('/api/walk-sessions/$sessionId/members', token: _token);
    final raw = response['members'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchInvites() async {
    final response = await _api.getJson('/api/walk-invites', token: _token);
    final raw = response['invites'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchInviteCandidates() async {
    final response = await _api.getJson('/api/walk-invite-candidates', token: _token);
    final raw = response['users'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchRecordedWalks() async {
    final response = await _api.getJson('/api/recorded-walks', token: _token);
    final raw = response['walks'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Stream<List<Map<String, dynamic>>> watchSessions(String userId) =>
      _poll(() => fetchSessions(userId), fallback: const <Map<String, dynamic>>[]);

  Stream<List<Map<String, dynamic>>> watchMembers(String sessionId) =>
      _poll(() => fetchMembers(sessionId), fallback: const <Map<String, dynamic>>[]);

  Stream<List<Map<String, dynamic>>> watchInvites() =>
      _poll(fetchInvites, fallback: const <Map<String, dynamic>>[]);

  Stream<List<Map<String, dynamic>>> watchRecordedWalks() =>
      _poll(fetchRecordedWalks, fallback: const <Map<String, dynamic>>[]);

  Future<void> saveSession(Map<String, dynamic> payload) async {
    await _api.postJson('/api/walk-sessions', payload, token: _token);
  }

  Future<void> saveMember(String sessionId, Map<String, dynamic> payload) async {
    await _api.postJson('/api/walk-sessions/$sessionId/members', payload, token: _token);
  }

  Future<void> deleteMember(String sessionId, String userId) async {
    await _api.deleteJson('/api/walk-sessions/$sessionId/members/$userId', token: _token);
  }

  Future<void> saveInvite(Map<String, dynamic> payload) async {
    await _api.postJson('/api/walk-invites', payload, token: _token);
  }

  Future<void> updateInvite(String inviteId, String status) async {
    await _api.patchJson('/api/walk-invites/$inviteId', {'status': status}, token: _token);
  }

  Future<void> saveRecordedWalk(Map<String, dynamic> payload) async {
    await _api.postJson('/api/recorded-walks', payload, token: _token);
  }

  Future<void> deleteRecordedWalk(String walkId) async {
    await _api.deleteJson('/api/recorded-walks/$walkId', token: _token);
  }
}
