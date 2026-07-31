import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:selfcare_projects/src/services/step_map_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingRecordedWalkSyncService {
  PendingRecordedWalkSyncService._();

  static final PendingRecordedWalkSyncService instance =
      PendingRecordedWalkSyncService._();

  static String _queueKey(String userId) =>
      'pending_recorded_walk_syncs_$userId';

  Future<void> queue({
    required String userId,
    required Map<String, dynamic> payload,
  }) async {
    if (userId.isEmpty) return;
    final id = payload['id']?.toString();
    if (id == null || id.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final pending = await _load(prefs, userId);
    pending[id] = payload;
    await prefs.setString(_queueKey(userId), jsonEncode(pending));
  }

  Future<void> flush({required String userId}) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = await _load(prefs, userId);
    if (pending.isEmpty) return;

    final remaining = <String, Map<String, dynamic>>{};
    for (final entry in pending.entries) {
      try {
        await StepMapApiService.instance
            .saveRecordedWalk(entry.value)
            .timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint('Pending recorded walk retained for ${entry.key}: $error');
        remaining[entry.key] = entry.value;
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_queueKey(userId));
    } else {
      await prefs.setString(_queueKey(userId), jsonEncode(remaining));
    }
  }

  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey(userId));
  }

  Future<Map<String, Map<String, dynamic>>> _load(
    SharedPreferences prefs,
    String userId,
  ) async {
    await prefs.reload();
    final encoded = prefs.getString(_queueKey(userId));
    if (encoded == null || encoded.isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, Map<String, dynamic>>{};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          value is Map
              ? Map<String, dynamic>.from(value)
              : <String, dynamic>{},
        ),
      );
    } catch (error) {
      debugPrint('Pending recorded walk queue was invalid: $error');
      return <String, Map<String, dynamic>>{};
    }
  }
}
