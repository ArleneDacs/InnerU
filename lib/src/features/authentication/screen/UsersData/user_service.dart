import 'dart:async';
import 'dart:convert';

import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static final _api = ApiClient.instance;

  static String _cacheKey(String userId) => 'cached_user_data_$userId';

  /// Fetches the current user's profile. On a slow or unreachable network
  /// this falls back to the last successful response cached on-device
  /// (rather than surfacing an error or an empty map), so screens that read
  /// streaks/medals/scores from this data show the user's real last-known
  /// values instead of flashing to zero/locked while offline. The fresh
  /// value, once fetched, replaces the cache for next time.
  static Future<Map<String, dynamic>> getUserData() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return {};

    try {
      final response = await _api.getJson(
        '/api/me',
        token: session.token,
      );
      final user = response['user'];
      if (user is! Map<String, dynamic>) {
        return await _readCache(session.id.toString());
      }

      final normalized = _normalizeUserMap(user);
      unawaited(_writeCache(session.id.toString(), normalized));
      return normalized;
    } catch (error) {
      final cached = await _readCache(session.id.toString());
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _readCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(userId));
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeCache(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(userId), jsonEncode(data));
    } catch (_) {
      // Caching is a best-effort convenience; failing to persist it should
      // never surface as a user-facing error.
    }
  }

  static Future<Map<String, dynamic>> updateUserData({
    String? name,
    String? email,
    String? number,
    String? birthdate,
  }) async {
    return updateUserFields({
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (number != null) 'number': number,
      if (birthdate != null) 'birthdate': birthdate,
    });
  }

  static Future<Map<String, dynamic>> updateUserFields(
    Map<String, dynamic> payload,
  ) async {
    final session = AuthService.instance.currentSession;
    if (session == null || payload.isEmpty) return {};

    final response = await _api.patchJson(
      '/api/me',
      payload,
      token: session.token,
    );
    final user = response['user'];
    if (user is! Map<String, dynamic>) {
      return {};
    }

    final normalized = _normalizeUserMap(user);
    unawaited(_writeCache(session.id.toString(), normalized));
    return normalized;
  }

  static Map<String, dynamic> _normalizeUserMap(Map<String, dynamic> user) {
    return {
      ...user,
      'username': user['name']?.toString() ?? user['username']?.toString(),
      'profilePic': user['profile_pic']?.toString() ?? user['profilePic'],
      'profile_pic': user['profile_pic']?.toString(),
      'birthdate': user['birthdate']?.toString(),
      'number': user['number']?.toString(),
      'email': user['email']?.toString(),
    };
  }
}
