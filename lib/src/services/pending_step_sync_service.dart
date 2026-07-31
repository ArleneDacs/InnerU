import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';

class PendingStepSyncService {
  PendingStepSyncService._();

  static final PendingStepSyncService instance = PendingStepSyncService._();

  static String _queueKey(String userId) => 'pending_step_syncs_$userId';

  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey(userId));
  }

  Future<void> queueStepProgress({
    required String userId,
    required String date,
    required int stepCount,
    required int stepGoal,
    required bool steps,
    String? username,
    String? companyId,
    String? companyCode,
    String? companyName,
    bool preferLatestStepCount = false,
  }) async {
    if (userId.isEmpty || date.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final pending = await _loadQueue(prefs, userId);
    final existing = pending[date];
    final existingSteps = _asInt(existing?['step_count']);
    final resolvedStepCount = preferLatestStepCount
        ? stepCount
        : stepCount > existingSteps
            ? stepCount
            : existingSteps;

    pending[date] = <String, dynamic>{
      ...?existing,
      'date': date,
      'step_count': resolvedStepCount,
      'step_goal': stepGoal,
      'steps': steps || existing?['steps'] == true,
      if (username != null && username.isNotEmpty) 'username': username,
      if (companyId != null && companyId.isNotEmpty) 'company_id': companyId,
      if (companyCode != null && companyCode.isNotEmpty)
        'company_code': companyCode,
      if (companyName != null && companyName.isNotEmpty)
        'company_name': companyName,
    };

    await _saveQueue(prefs, userId, pending);
  }

  Future<void> flush({required String userId}) async {
    if (userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final pending = await _loadQueue(prefs, userId);
    if (pending.isEmpty) return;

    final remaining = <String, Map<String, dynamic>>{};
    final entries = pending.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in entries) {
      final payload = entry.value;
      try {
        await DailyTrackerApiService.instance.upsert(
          date: payload['date']?.toString() ?? entry.key,
          stepCount: _asInt(payload['step_count']),
          stepGoal: _asInt(payload['step_goal'], fallback: 5000),
          steps: payload['steps'] == true,
          username: payload['username']?.toString(),
          companyId: payload['company_id']?.toString(),
          companyCode: payload['company_code']?.toString(),
          companyName: payload['company_name']?.toString(),
        );
      } catch (error) {
        debugPrint('Pending step sync retained for ${entry.key}: $error');
        remaining[entry.key] = payload;
      }
    }

    await _saveQueue(prefs, userId, remaining);
  }

  Future<Map<String, Map<String, dynamic>>> _loadQueue(
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
      if (decoded is! Map) {
        return <String, Map<String, dynamic>>{};
      }
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{},
        ),
      );
    } catch (error) {
      debugPrint('Pending step sync queue was invalid: $error');
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _saveQueue(
    SharedPreferences prefs,
    String userId,
    Map<String, Map<String, dynamic>> pending,
  ) async {
    if (pending.isEmpty) {
      await prefs.remove(_queueKey(userId));
      return;
    }
    await prefs.setString(_queueKey(userId), jsonEncode(pending));
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }
}
