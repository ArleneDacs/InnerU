import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class EmotionSaveResult {
  const EmotionSaveResult({
    required this.created,
    required this.emotion,
    this.previousEmotion,
  });

  final bool created;
  final String? emotion;
  final String? previousEmotion;
}

class EmotionService {
  EmotionService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient.instance;

  final ApiClient _api;

  static String todayKey([DateTime? now]) => dateKeyFor(now ?? DateTime.now());

  static String dateKeyFor(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Stream<String?> watchTodayEmotion(String userId, {DateTime? now}) async* {
    yield await fetchTodayEmotion(userId, now: now);
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 30));
      yield await fetchTodayEmotion(userId, now: now);
    }
  }

  Future<String?> fetchTodayEmotion(String userId, {DateTime? now}) async {
    try {
      final response = await _api.getJson(
        '/api/emotions/today?date=${dateKeyFor(now ?? DateTime.now())}',
        token: AuthService.instance.currentSession?.token,
      );
      return response['emotion']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchHistory({String? month}) async {
    final query = <String, String>{};
    if (month != null && month.isNotEmpty) {
      query['month'] = month;
    }

    final path = query.isEmpty
        ? '/api/emotions/history'
        : Uri(path: '/api/emotions/history', queryParameters: query).toString();

    try {
      final response = await _api.getJson(
        path,
        token: AuthService.instance.currentSession?.token,
      );
      final emotions = response['emotions'];
      if (emotions is List) {
        return emotions
            .whereType<Map>()
            .map((emotion) => Map<String, dynamic>.from(emotion))
            .toList();
      }
    } catch (_) {}

    return const [];
  }

  Future<EmotionSaveResult> saveTodayEmotion({
    required String userId,
    required String username,
    required String emotion,
    DateTime? now,
  }) async {
    final savedAt = now ?? DateTime.now();
    final today = dateKeyFor(savedAt);
    final normalizedEmotion = _normalizeEmotion(emotion) ?? emotion.trim();
    final normalizedUsername =
        username.trim().isEmpty ? 'Unknown' : username.trim();
    final previousEmotion = await fetchTodayEmotion(userId, now: now);

    await _api.postJson(
      '/api/emotions/today',
      {
        'emotion': normalizedEmotion,
        'username': normalizedUsername,
        'date': today,
        'logged_at': savedAt.toIso8601String(),
      },
      token: AuthService.instance.currentSession?.token,
    );

    WatchSyncService.instance.syncMood(normalizedEmotion, savedAt);
    return EmotionSaveResult(
      created: previousEmotion == null,
      emotion: normalizedEmotion,
      previousEmotion: previousEmotion,
    );
  }

  String? _normalizeEmotion(dynamic value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
