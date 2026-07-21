import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/fasting_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

/// Pushes the user's current known state to the watch so it mirrors
/// reality on app open, not only when new events happen. Includes weekly
/// summaries, awards, and mood history for the watch detail screens.
/// Fire-and-forget: failures are logged, never thrown.
class WatchStateRefresher {
  WatchStateRefresher();

  Future<void> refresh(String userId) async {
    Map<String, dynamic> userData = <String, dynamic>{};
    CompanyMembership? membership;
    try {
      userData = await UserService.getUserData();
      membership =
          (await CompanyMembershipService.loadForUser(userId)).activeMembership;
    } catch (error) {
      debugPrint('Watch refresh prefetch failed: $error');
    }

    await Future.wait([
      _refreshSteps(userId, userData, membership),
      _refreshMood(userId),
      _refreshMeditation(userId, userData, membership),
      _refreshFasting(userId),
    ]);
  }

  List<String> _lastSevenDayKeys() {
    final now = DateTime.now();
    return List.generate(
      7,
      (index) => isoDay(now.subtract(Duration(days: 6 - index))),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _trackerHistoryByDate() async {
    final now = DateTime.now();
    final months = <String>{
      DateFormat('yyyy-MM').format(now),
      DateFormat('yyyy-MM').format(DateTime(now.year, now.month - 1, 1)),
    };

    final history = <String, Map<String, dynamic>>{};
    for (final month in months) {
      try {
        final trackers = await DailyTrackerApiService.instance.fetchHistory(
          month: month,
        );
        for (final tracker in trackers) {
          final date = tracker['date']?.toString();
          if (date == null || date.isEmpty) continue;
          history[date] = tracker;
        }
      } catch (error) {
        debugPrint('Watch tracker history load failed: $error');
      }
    }
    return history;
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
    CompanyMembership? membership,
  ) async {
    try {
      final historyByDate = await _trackerHistoryByDate();
      final weekly = <Map<String, Object>>[];
      for (final key in _lastSevenDayKeys()) {
        final doc = historyByDate[key];
        weekly.add({
          'd': key,
          'v': (doc?['stepCount'] as num?)?.toInt() ?? 0,
        });
      }

      final prefs = await SharedPreferences.getInstance();
      // The local step cache is only trustworthy if it belongs to this
      // user; today's dailytracker doc is the fallback (synced from any
      // device, including the watch itself).
      final owner = prefs.getString(SessionCleanupService.stepCacheOwnerKey);
      final localSteps = owner == userId
          ? prefs.getInt(SessionCleanupService.savedStepsKey(userId)) ?? 0
          : 0;
      final remoteToday =
          (historyByDate[_lastSevenDayKeys().last]?['stepCount'] as num?)
                  ?.toInt() ??
              0;
      final historyToday = weekly.last['v'] as int;
      final steps = [localSteps, remoteToday, historyToday]
          .reduce((a, b) => a > b ? a : b);
      weekly.last['v'] = steps;
      // The goal is stored per-user, so it needs no ownership check.
      final goal = prefs.getInt('daily_step_goal_$userId');
      WatchSyncService.instance.syncSteps(steps, goal: goal, force: true);

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
      final emotion = await EmotionService().fetchTodayEmotion(userId);
      final logs = <Map<String, Object>>[];
      final currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
      final historyRecords = await EmotionService().fetchHistory(
        month: currentMonth,
      );
      final latestRecord = historyRecords.isNotEmpty ? historyRecords.last : null;
      final history = latestRecord?['history'];
      if (history is List) {
        for (final entry in history) {
          if (entry is Map) {
            final mood = (entry['emotion'] as String?)?.trim();
            final at = entry['loggedAt']?.toString();
            final parsedAt = DateTime.tryParse(at ?? '');
            if (mood != null && mood.isNotEmpty && parsedAt != null) {
              logs.add({'m': mood, 'atMs': parsedAt.millisecondsSinceEpoch});
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

      final historyByDate = await _trackerHistoryByDate();
      final weekly = <Map<String, Object>>[];
      for (final key in _lastSevenDayKeys()) {
        final doc = historyByDate[key];
        weekly.add({
          'd': key,
          'v': (doc?['meditationMinutes'] as num?)?.toInt() ?? 0,
        });
      }
      WatchSyncService.instance.syncExtras({'weeklyMeditation': weekly});
    } catch (error) {
      debugPrint('Watch meditation refresh failed: $error');
    }
  }

  Future<void> _refreshFasting(String userId) async {
    try {
      final response = await FastingApiService.instance.fetchSession();
      final data = response['session'];
      if (data is! Map) return;
      final session = Map<String, dynamic>.from(data);
      final start = DateTime.tryParse(session['startTime']?.toString() ?? '');
      final end = DateTime.tryParse(session['endTime']?.toString() ?? '');
      final active = start != null && end != null;
      WatchSyncService.instance.syncFasting(
        active: active,
        start: start,
        goalHours: (session['targetHours'] as num?)?.toInt(),
      );
    } catch (error) {
      debugPrint('Watch fasting refresh failed: $error');
    }
  }
}
