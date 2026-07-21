import 'dart:async';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class ChatApiService {
  ChatApiService._();

  static final ChatApiService instance = ChatApiService._();

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

  Future<List<Map<String, dynamic>>> fetchRooms(String userId) async {
    final response = await _api.getJson(
      '/api/chat-rooms?userId=$userId',
      token: _token,
    );
    final raw = response['rooms'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((room) => Map<String, dynamic>.from(room))
        .toList();
  }

  Future<Map<String, dynamic>?> fetchRoom(String roomId) async {
    try {
      final response = await _api.getJson('/api/chat-rooms/$roomId', token: _token);
      final raw = response['room'];
      if (raw is! Map<String, dynamic>) return null;
      return raw;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String roomId) async {
    final response = await _api.getJson(
      '/api/chat-rooms/$roomId/messages',
      token: _token,
    );
    final raw = response['messages'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
  }

  Stream<List<Map<String, dynamic>>> watchRooms(String userId) =>
      _poll(() => fetchRooms(userId), fallback: const <Map<String, dynamic>>[]);

  Stream<Map<String, dynamic>?> watchRoom(String roomId) =>
      _poll(() => fetchRoom(roomId), fallback: null);

  Stream<List<Map<String, dynamic>>> watchMessages(String roomId) =>
      _poll(() => fetchMessages(roomId), fallback: const <Map<String, dynamic>>[]);

  Future<Map<String, dynamic>> saveRoom(Map<String, dynamic> payload) async {
    final response = await _api.postJson(
      '/api/chat-rooms',
      payload,
      token: _token,
    );
    final raw = response['room'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Chat room response was invalid.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> sendMessage(
    String roomId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _api.postJson(
      '/api/chat-rooms/$roomId/messages',
      payload,
      token: _token,
    );
    final raw = response['message'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Message response was invalid.');
    }
    return raw;
  }

  Future<Map<String, dynamic>> markRead(String roomId) async {
    final response = await _api.patchJson(
      '/api/chat-rooms/$roomId/read',
      const <String, dynamic>{},
      token: _token,
    );
    final raw = response['room'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException(500, 'Read response was invalid.');
    }
    return raw;
  }
}
