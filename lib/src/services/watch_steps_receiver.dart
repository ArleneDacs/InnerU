import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_snapshot.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

/// Receives step counts measured by the Apple Watch's own sensors and
/// records them to Firestore alongside phone-counted steps. The watch
/// queues its latest count while the phone is away; iOS delivers it when
/// the devices reconnect (or instantly when both apps are live).
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
  }

  Future<void> _handle(Map<String, dynamic> data) async {
    try {
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

      final membershipData =
          await CompanyMembershipService.loadForUser(user.uid);
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
    } catch (error) {
      debugPrint('Watch steps recording failed: $error');
    }
  }
}
