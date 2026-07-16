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

  void syncMood(String mood, DateTime at) {
    if (!_enabled) return;
    _push({'mood': mood, 'moodAtMs': at.millisecondsSinceEpoch});
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
      await _watch.updateApplicationContext(
        Map<String, dynamic>.from(_snapshot.data),
      );
    } catch (error) {
      debugPrint('Watch sync failed: $error');
    }
  }
}
