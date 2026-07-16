import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_snapshot.dart';
import 'package:selfcare_projects/src/services/watch_state_refresher.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

/// Phone-side bridge for everything the watch sends: step counts from
/// the watch's own sensors, refresh requests, and action commands
/// (start/end fast, meditation completed on watch, mood logged on watch).
/// Commands are deduplicated by id, so queued re-deliveries are safe.
class WatchStepsReceiver {
  WatchStepsReceiver._();

  static final WatchStepsReceiver instance = WatchStepsReceiver._();

  final WatchConnectivity _watch = WatchConnectivity();
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _contextSub;

  void start() {
    if (kIsWeb || !Platform.isIOS) return;
    _messageSub ??= _watch.messageStream.listen(_handle);
    _contextSub ??= _watch.contextStream.listen(_handle);
    WidgetsBinding.instance.addObserver(_WatchResumeObserver());
  }

  Future<void> _handle(Map<String, dynamic> data) async {
    try {
      if (data['requestRefresh'] == true) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await WatchStateRefresher().refresh(uid);
        }
        return;
      }

      final single = data['command'];
      if (single is Map) {
        await _processCommand(Map<String, dynamic>.from(single));
        return;
      }

      final pending = data['pendingCommands'];
      if (pending is List) {
        for (final command in pending) {
          if (command is Map) {
            await _processCommand(Map<String, dynamic>.from(command));
          }
        }
      }

      await _handleSteps(data);
    } catch (error) {
      debugPrint('Watch data handling failed: $error');
    }
  }

  Future<void> _handleSteps(Map<String, dynamic> data) async {
    final steps = (data['watchSteps'] as num?)?.toInt();
    final date = data['watchStepsDate'] as String?;
    if (steps == null || steps <= 0 || date == null) return;
    if (date != dayKey(DateTime.now())) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final recordedKey = 'watch_steps_${user.uid}_$date';
    final alreadyRecorded = prefs.getInt(recordedKey) ?? 0;
    if (steps <= alreadyRecorded) return;
    await prefs.setInt(recordedKey, steps);

    // Both devices count the same walk: record the higher, never the sum.
    final phoneSteps =
        prefs.getInt(SessionCleanupService.savedStepsKey(user.uid)) ?? 0;
    final combined = steps > phoneSteps ? steps : phoneSteps;

    final membershipData = await CompanyMembershipService.loadForUser(user.uid);
    final trackerDocId = CompanyMembershipService.scopedDailyDocId(
      uid: user.uid,
      date: date,
      membership: membershipData.activeMembership,
    );
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('dailytracker').doc(trackerDocId).set({
      'stepCount': combined,
      'date': date,
      ...CompanyMembershipService.activeCompanyFields(
        membershipData.activeMembership,
      ),
    }, SetOptions(merge: true));
    await firestore
        .collection('steps')
        .doc(user.uid)
        .collection('tracking')
        .doc(date)
        .set({
      'steps': combined,
      'timestamp': DateTime.parse(date).millisecondsSinceEpoch,
    }, SetOptions(merge: true));

    // Reflect the merged count back to the watch/widget snapshot.
    WatchSyncService.instance.syncSteps(combined);

    debugPrint('Recorded $steps watch steps ($combined combined) for $date');
  }

  Future<void> _processCommand(Map<String, dynamic> command) async {
    final id = command['id'] as String?;
    final type = command['type'] as String?;
    if (id == null || type == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final processedKey = 'watch_cmd_ids_${user.uid}';
    final processed = prefs.getStringList(processedKey) ?? <String>[];
    if (processed.contains(id)) return;

    final atMs = (command['atMs'] as num?)?.toInt();
    final at = atMs == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(atMs);

    switch (type) {
      case 'startFast':
        await _startFast(user.uid, command, at);
      case 'endFast':
        await _endFast(user.uid, at);
      case 'meditationCompleted':
        final seconds = (command['seconds'] as num?)?.toInt() ?? 0;
        await _recordMeditation(user, seconds, at);
      case 'logMood':
        await _logMood(user, command['mood'] as String?, at);
      default:
        debugPrint('Unknown watch command: $type');
    }

    processed.add(id);
    if (processed.length > 100) {
      processed.removeRange(0, processed.length - 100);
    }
    await prefs.setStringList(processedKey, processed);
    await WatchStateRefresher().refresh(user.uid);
    debugPrint('Applied watch command $type ($id)');
  }

  DocumentReference<Map<String, dynamic>> _fastingRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wellness')
        .doc('fasting');
  }

  Future<void> _startFast(
    String uid,
    Map<String, dynamic> command,
    DateTime at,
  ) async {
    final goal = (command['goalHours'] as num?)?.toInt() ?? 16;
    await _fastingRef(uid).set({
      'targetHours': goal,
      'startTime': Timestamp.fromDate(at),
      'endTime': Timestamp.fromDate(at.add(Duration(hours: goal))),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    WatchSyncService.instance
        .syncFasting(active: true, start: at, goalHours: goal);
  }

  Future<void> _endFast(String uid, DateTime at) async {
    final ref = _fastingRef(uid);
    final snapshot = await ref.get();
    final data = snapshot.data();
    final startedAt = (data?['startTime'] as Timestamp?)?.toDate();
    final plannedEnd = (data?['endTime'] as Timestamp?)?.toDate();
    final target = (data?['targetHours'] as num?)?.toInt() ?? 16;

    var completedTarget = false;
    if (startedAt != null) {
      final durationHours = at.difference(startedAt).inMinutes / 60.0;
      completedTarget = plannedEnd != null && !at.isBefore(plannedEnd);
      await ref.collection('history').add({
        'targetHours': target,
        'startTime': Timestamp.fromDate(startedAt),
        'plannedEndTime':
            plannedEnd == null ? null : Timestamp.fromDate(plannedEnd),
        'finishedAt': Timestamp.fromDate(at),
        'completedHours': double.parse(durationHours.toStringAsFixed(2)),
        'completedTarget': completedTarget,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await ref.set({
      'startTime': null,
      'endTime': null,
      'lastCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (completedTarget) {
      await ActivityStreakService().recordCompletedSession(
        userId: uid,
        type: ActivityStreakType.fasting,
        completedAt: at,
      );
    }
    WatchSyncService.instance.syncFasting(active: false);
  }

  Future<void> _recordMeditation(User user, int seconds, DateTime at) async {
    final firestore = FirebaseFirestore.instance;
    final userDoc = await firestore.collection('users').doc(user.uid).get();
    final username = userDoc.data()?['username'];

    if (username != null) {
      final formattedDate = dayKey(at);
      final membershipData =
          await CompanyMembershipService.loadForUser(user.uid);
      final trackerDocId = CompanyMembershipService.scopedDailyDocId(
        uid: user.uid,
        date: formattedDate,
        membership: membershipData.activeMembership,
      );
      final minutes =
          seconds <= 0 ? null : (seconds / Duration.secondsPerMinute).ceil();
      await firestore.collection('dailytracker').doc(trackerDocId).set({
        'userId': user.uid,
        'username': username,
        'date': formattedDate,
        'meditation': true,
        if (minutes != null) 'meditationMinutes': FieldValue.increment(minutes),
        ...CompanyMembershipService.activeCompanyFields(
          membershipData.activeMembership,
        ),
      }, SetOptions(merge: true));
    }

    await MeditationStreakService()
        .recordCompletedSession(userId: user.uid, completedAt: at);
  }

  Future<void> _logMood(User user, String? mood, DateTime at) async {
    if (mood == null || mood.trim().isEmpty) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final username = (userDoc.data()?['username'] as String?) ?? 'Unknown';
    await EmotionService().saveTodayEmotion(
      user: user,
      emotion: mood,
      username: username,
      now: at,
    );
  }
}

/// Re-pushes current state to the watch whenever the phone app returns
/// to the foreground, so the two stay in sync without user action.
class _WatchResumeObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    unawaited(WatchStateRefresher().refresh(uid));
  }
}
