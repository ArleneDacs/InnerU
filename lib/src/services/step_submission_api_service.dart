import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class StepSubmissionApiService {
  StepSubmissionApiService._();

  static final StepSubmissionApiService instance = StepSubmissionApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Stream<T> _poll<T>(
    Future<T> Function() fetch, {
    required T fallback,
    Duration interval = const Duration(seconds: 15),
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
      Map<String, dynamic> response, String key) {
    final raw = response[key];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> submit({
    required int steps,
    required String date,
    required String proofUrl,
    String? note,
  }) async {
    final response = await _api.postJson(
      '/api/step-submissions',
      {
        'steps': steps,
        'date': date,
        'proof_url': proofUrl,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      token: _token,
    );
    final raw = response['submission'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Step submission response was invalid.');
    }
    return raw;
  }

  Future<List<Map<String, dynamic>>> fetchMine() async {
    final response =
        await _api.getJson('/api/step-submissions/mine', token: _token);
    return _listFrom(response, 'submissions');
  }

  Stream<List<Map<String, dynamic>>> watchMine() =>
      _poll(fetchMine, fallback: const <Map<String, dynamic>>[]);

  Future<List<Map<String, dynamic>>> fetchForCoach({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final response = await _api.getJson(
      '/api/coach/step-submissions$query',
      token: _token,
    );
    return _listFrom(response, 'submissions');
  }

  Stream<List<Map<String, dynamic>>> watchForCoach({String? status}) => _poll(
        () => fetchForCoach(status: status),
        fallback: const <Map<String, dynamic>>[],
      );

  Future<Map<String, dynamic>> approve(String submissionId) async {
    final response = await _api.patchJson(
      '/api/coach/step-submissions/$submissionId/approve',
      const {},
      token: _token,
    );
    final raw = response['submission'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Approve response was invalid.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> decline(
      String submissionId, String reason) async {
    final response = await _api.patchJson(
      '/api/coach/step-submissions/$submissionId/decline',
      {'reason': reason},
      token: _token,
    );
    final raw = response['submission'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Decline response was invalid.');
    }
    return raw;
  }
}
