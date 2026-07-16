import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_snapshot.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

/// Pushes the user's current known state to the watch so it mirrors
/// reality on app open, not only when new events happen. Includes weekly
/// summaries, awards, and mood history for the watch detail screens.
/// Fire-and-forget: failures are logged, never thrown.
class WatchStateRefresher {
  WatchStateRefresher({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> refresh(String userId) async {
    Map<String, dynamic> userData = <String, dynamic>{};
    CompanyMembership? membership;
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      userData = userDoc.data() ?? <String, dynamic>{};
      membership =
          (await CompanyMembershipService.loadForUser(userId)).activeMembership;
    } catch (error) {
      debugPrint('Watch refresh prefetch failed: $error');
    }

    await Future.wait([
      _refreshSteps(userId, userData),
      _refreshMood(userId),
      _refreshMeditation(userId, userData, membership),
      _refreshFasting(userId),
    ]);
  }

  List<String> _lastSevenDayKeys() {
    final now = DateTime.now();
    return List.generate(
      7,
      (index) => dayKey(now.subtract(Duration(days: 6 - index))),
    );
  }

  int _streakFor(ActivityStreakType type, Map<String, dynamic> userData) {
    return ActivityStreakService.activeCurrentStreak(
      lastDate: userData[ActivityStreakService.lastDateFieldFor(type)],
      currentStreak: ActivityStreakService.readInt(
        userData[ActivityStreakService.currentFieldFor(type)],
      ),
    );
  }

  List<String> _awardsFor(ActivityStreakType type, Map<String, dynamic> userData) {
    final rewards = ActivityStreakService.readRewards(
      userData[ActivityStreakService.rewardsFieldFor(type)],
    );
    return ActivityStreakService.milestonesFor(type)
        .where((milestone) => rewards.containsKey(milestone.id))
        .map((milestone) => '${milestone.tier} · ${milestone.title}')
        .toList();
  }

  Future<void> _refreshSteps(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(SessionCleanupService.stepCacheOwnerKey);
      if (owner == userId) {
        final steps =
            prefs.getInt(SessionCleanupService.savedStepsKey(userId));
        if (steps != null) {
          final goal = prefs.getInt('daily_step_goal_$userId');
          WatchSyncService.instance.syncSteps(steps, goal: goal);
        }
      }

      final weekly = <Map<String, Object>>[];
      for (final key in _lastSevenDayKeys()) {
        final doc = await _firestore
            .collection('steps')
            .doc(userId)
            .collection('tracking')
            .doc(key)
            .get();
        weekly.add({
          'd': key,
          'v': (doc.data()?['steps'] as num?)?.toInt() ?? 0,
        });
      }

      WatchSyncService.instance.syncExtras({
        'weeklySteps': weekly,
        'stepStreak': _streakFor(ActivityStreakType.steps, userData),
        'stepAwards': _awardsFor(ActivityStreakType.steps, userData),
      });
    } catch (error) {
      debugPrint('Watch steps refresh failed: $error');
    }
  }

  Future<void> _refreshMood(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('emotions')
          .where('userId', isEqualTo: userId)
          .where('date', isEqualTo: dayKey(DateTime.now()))
          .get();
      if (snapshot.docs.isEmpty) return;
      final data = snapshot.docs.first.data();

      final emotion = (data['emotion'] as String?)?.trim();
      final logs = <Map<String, Object>>[];
      final history = data['history'];
      if (history is List) {
        for (final entry in history) {
          if (entry is Map) {
            final mood = (entry['emotion'] as String?)?.trim();
            final at = entry['loggedAt'];
            if (mood != null && mood.isNotEmpty && at is Timestamp) {
              logs.add({'m': mood, 'atMs': at.millisecondsSinceEpoch});
            }
          }
        }
      }
      if (logs.length > 7) {
        logs.removeRange(0, logs.length - 7);
      }

      if (emotion != null && emotion.isNotEmpty) {
        final lastAt = logs.isEmpty
            ? null
            : DateTime.fromMillisecondsSinceEpoch(logs.last['atMs'] as int);
        WatchSyncService.instance.syncMood(emotion.toLowerCase(), lastAt);
      }
      WatchSyncService.instance.syncExtras({'moodLogs': logs});
    } catch (error) {
      debugPrint('Watch mood refresh failed: $error');
    }
  }

  Future<void> _refreshMeditation(
    String userId,
    Map<String, dynamic> userData,
    CompanyMembership? membership,
  ) async {
    try {
      final lastDate = userData[ActivityStreakService.lastDateFieldFor(
        ActivityStreakType.meditation,
      )] as String?;
      if (lastDate != null && lastDate.isNotEmpty) {
        WatchSyncService.instance.syncMeditation(
          streak: _streakFor(ActivityStreakType.meditation, userData),
          completedAt: DateTime.tryParse(lastDate),
        );
      }

      final weekly = <Map<String, Object>>[];
      for (final key in _lastSevenDayKeys()) {
        final docId = CompanyMembershipService.scopedDailyDocId(
          uid: userId,
          date: key,
          membership: membership,
        );
        final doc =
            await _firestore.collection('dailytracker').doc(docId).get();
        weekly.add({
          'd': key,
          'v': (doc.data()?['meditationMinutes'] as num?)?.toInt() ?? 0,
        });
      }
      WatchSyncService.instance.syncExtras({'weeklyMeditation': weekly});
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
