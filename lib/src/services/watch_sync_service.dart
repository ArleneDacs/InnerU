import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'package:selfcare_projects/src/services/watch_snapshot.dart';

/// Pushes activity state to the Apple Watch companion app.
/// Fire-and-forget: failures are logged and never thrown.
class WatchSyncService {
  WatchSyncService._();

  static final WatchSyncService instance = WatchSyncService._();

  final WatchConnectivity _watch = WatchConnectivity();
  final WatchSnapshot _snapshot = WatchSnapshot();
  final StepSyncGate _stepGate = StepSyncGate();

  bool get _enabled => !kIsWeb && Platform.isIOS;

  void syncSteps(int steps, {int? goal}) {
    if (!_enabled) return;
    final now = DateTime.now();
    if (!_stepGate.shouldSync(steps, now)) return;
    _push({
      'steps': steps,
      if (goal != null) 'stepGoal': goal,
      'stepsDate': dayKey(now),
    });
  }

  void syncFasting({required bool active, DateTime? start, int? goalHours}) {
    if (!_enabled) return;
    _push({
      'fastingActive': active,
      if (active && start != null)
        'fastingStartMs': start.millisecondsSinceEpoch,
      if (active && goalHours != null) 'fastingGoalHours': goalHours,
    });
  }

  void syncMeditation({required int streak, DateTime? completedAt}) {
    if (!_enabled) return;
    _push({
      'meditatedOn': dayKey(completedAt ?? DateTime.now()),
      'meditationStreak': streak,
    });
  }

  /// Live meditation session state. While active the watch shows a
  /// countdown to [endsAt], ticking locally without further updates.
  void syncMeditationSession({required bool active, DateTime? endsAt}) {
    if (!_enabled) return;
    _push({
      'meditationActive': active,
      if (active && endsAt != null)
        'meditationEndsAtMs': endsAt.millisecondsSinceEpoch,
    });
  }

  void syncMood(String mood, [DateTime? at]) {
    if (!_enabled) return;
    _push({'mood': mood, if (at != null) 'moodAtMs': at.millisecondsSinceEpoch});
  }

  /// Pushes additional snapshot keys (weekly summaries, awards, logs).
  /// Values must be property-list-safe (numbers, strings, lists, maps).
  void syncExtras(Map<String, Object?> data) {
    if (!_enabled) return;
    _push(data);
  }

  void _push(Map<String, Object?> updates) {
    _snapshot.merge(updates);
    _snapshot.merge({'updatedAtMs': DateTime.now().millisecondsSinceEpoch});
    unawaited(_send());
  }

  Future<void> _send() async {
    try {
      if (!await _watch.isSupported) return;
      if (!await _watch.isPaired) return;
      final payload = Map<String, dynamic>.from(_snapshot.data);
      // Application context: persisted "latest state", delivered even if
      // the watch app is closed.
      await _watch.updateApplicationContext(payload);
      // Live message: instant delivery while the watch app is open.
      if (await _watch.isReachable) {
        await _watch.sendMessage(payload);
      }
    } catch (error) {
      debugPrint('Watch sync failed: $error');
    }
  }
}
