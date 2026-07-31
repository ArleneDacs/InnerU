import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class AccountabilityMeetingApiService {
  AccountabilityMeetingApiService._();

  static final AccountabilityMeetingApiService instance =
      AccountabilityMeetingApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Stream<T> _poll<T>(
    Future<T> Function() fetch, {
    required T fallback,
    Duration interval = const Duration(seconds: 20),
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

  List<Map<String, dynamic>> _listFrom(
    Map<String, dynamic> response,
    String key,
  ) {
    final raw = response[key];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> schedule({
    required String groupId,
    required String title,
    required String zoomLink,
    required DateTime scheduledAt,
    String? notes,
  }) async {
    final response = await _api.postJson(
      '/api/accountability-meetings',
      {
        'group_id': groupId,
        'title': title,
        'zoom_link': zoomLink,
        'scheduled_at': scheduledAt.toIso8601String(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      token: _token,
    );
    final raw = response['meeting'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Schedule meeting response was invalid.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> update({
    required String meetingId,
    required String title,
    required String zoomLink,
    required DateTime scheduledAt,
    String? notes,
  }) async {
    final response = await _api.patchJson(
      '/api/accountability-meetings/$meetingId',
      {
        'title': title,
        'zoom_link': zoomLink,
        'scheduled_at': scheduledAt.toIso8601String(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      token: _token,
    );
    final raw = response['meeting'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Update meeting response was invalid.');
    }
    return raw;
  }

  Future<void> delete(String meetingId) async {
    await _api.deleteJson(
      '/api/accountability-meetings/$meetingId',
      token: _token,
    );
  }

  Future<List<Map<String, dynamic>>> fetchForCoach() async {
    final response = await _api.getJson(
      '/api/coach/accountability-meetings',
      token: _token,
    );
    return _listFrom(response, 'meetings');
  }

  Stream<List<Map<String, dynamic>>> watchForCoach() =>
      _poll(fetchForCoach, fallback: const <Map<String, dynamic>>[]);

  Future<List<Map<String, dynamic>>> fetchMine() async {
    final response = await _api.getJson(
      '/api/accountability-meetings/mine',
      token: _token,
    );
    return _listFrom(response, 'meetings');
  }

  Stream<List<Map<String, dynamic>>> watchMine() =>
      _poll(fetchMine, fallback: const <Map<String, dynamic>>[]);

  Future<Map<String, dynamic>> join(String meetingId) async {
    final response = await _api.postJson(
      '/api/accountability-meetings/$meetingId/join',
      const {},
      token: _token,
    );
    return response;
  }
}
