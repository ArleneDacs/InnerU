import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class NotificationApiService {
  NotificationApiService._();

  static final NotificationApiService instance = NotificationApiService._();

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Stream<T> _poll<T>(
    Future<T> Function() fetch, {
    required T fallback,
    Duration interval = const Duration(seconds: 10),
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

  Future<Map<String, dynamic>> fetchNotifications() async {
    final response = await _api.getJson('/api/notifications', token: _token);
    final raw = response['notifications'];
    final notifications = raw is List
        ? raw.whereType<Map>().map((n) => Map<String, dynamic>.from(n)).toList()
        : <Map<String, dynamic>>[];
    final unreadCountRaw = response['unreadCount'];
    final unreadCount = unreadCountRaw is int
        ? unreadCountRaw
        : unreadCountRaw is num
            ? unreadCountRaw.toInt()
            : 0;
    return {
      'notifications': notifications,
      'unreadCount': unreadCount,
    };
  }

  Stream<Map<String, dynamic>> watchNotifications() => _poll(
        fetchNotifications,
        fallback: const {
          'notifications': <Map<String, dynamic>>[],
          'unreadCount': 0,
        },
      );

  Future<void> markRead(String notificationId) async {
    await _api.patchJson(
      '/api/notifications/$notificationId/read',
      const {},
      token: _token,
    );
  }

  Future<void> markAllRead() async {
    await _api.patchJson('/api/notifications/read-all', const {},
        token: _token);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _api.deleteJson(
      '/api/notifications/$notificationId',
      token: _token,
    );
  }

  Future<void> reportStreakMilestone({
    required String milestone,
    required int days,
    required String activity,
  }) async {
    await _api.postJson(
      '/api/notifications/streak',
      {
        'milestone': milestone,
        'days': days,
        'activity': activity,
      },
      token: _token,
    );
  }
}
