import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

/// Pushes the user's current known state to the watch so it mirrors
/// reality on app open, not only when new events happen.
/// Fire-and-forget: failures are logged, never thrown.
class WatchStateRefresher {
  WatchStateRefresher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> refresh(String userId) async {
    await Future.wait([
      _refreshSteps(userId),
      _refreshMood(userId),
      _refreshMeditation(userId),
      _refreshFasting(userId),
    ]);
  }

  Future<void> _refreshSteps(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(SessionCleanupService.stepCacheOwnerKey);
      if (owner != userId) return;
      final steps = prefs.getInt(SessionCleanupService.savedStepsKey(userId));
      if (steps == null) return;
      final goal = prefs.getInt('daily_step_goal_$userId');
      WatchSyncService.instance.syncSteps(steps, goal: goal);
    } catch (error) {
      debugPrint('Watch steps refresh failed: $error');
    }
  }

  Future<void> _refreshMood(String userId) async {
    try {
      final emotion =
          await EmotionService(firestore: _firestore).fetchTodayEmotion(userId);
      if (emotion == null) return;
      WatchSyncService.instance.syncMood(emotion);
    } catch (error) {
      debugPrint('Watch mood refresh failed: $error');
    }
  }

  Future<void> _refreshMeditation(String userId) async {
    try {
      final snapshot =
          await _firestore.collection('users').doc(userId).get();
      final data = snapshot.data() ?? <String, dynamic>{};
      final lastDate = data[ActivityStreakService.lastDateFieldFor(
        ActivityStreakType.meditation,
      )] as String?;
      if (lastDate == null || lastDate.isEmpty) return;
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: lastDate,
        currentStreak: ActivityStreakService.readInt(
          data[ActivityStreakService.currentFieldFor(
            ActivityStreakType.meditation,
          )],
        ),
      );
      WatchSyncService.instance.syncMeditation(
        streak: streak,
        completedAt: DateTime.tryParse(lastDate),
      );
    } catch (error) {
      debugPrint('Watch meditation refresh failed: $error');
    }
  }

  Future<void> _refreshFasting(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('wellness')
          .doc('fasting')
          .get();
      final data = snapshot.data();
      if (data == null) return;
      final start = (data['startTime'] as Timestamp?)?.toDate();
      final end = (data['endTime'] as Timestamp?)?.toDate();
      final active = start != null && end != null;
      WatchSyncService.instance.syncFasting(
        active: active,
        start: start,
        goalHours: (data['targetHours'] as num?)?.toInt(),
      );
    } catch (error) {
      debugPrint('Watch fasting refresh failed: $error');
    }
  }
}
