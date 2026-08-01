import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/services/apple_health_steps_service.dart';
import 'package:selfcare_projects/src/services/pending_step_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Apple Health step sync', () {
    test('only access-related failures should request the access dialog', () {
      expect(
        const AppleHealthStepSyncResult(
          status: AppleHealthStepSyncStatus.permissionDenied,
        ).shouldRequestAccess,
        isTrue,
      );
      expect(
        const AppleHealthStepSyncResult(
          status: AppleHealthStepSyncStatus.unavailable,
        ).shouldRequestAccess,
        isTrue,
      );
      expect(
        const AppleHealthStepSyncResult(
          status: AppleHealthStepSyncStatus.accessMayBeDisabled,
        ).shouldRequestAccess,
        isTrue,
      );
      expect(
        const AppleHealthStepSyncResult(
          status: AppleHealthStepSyncStatus.queryFailed,
        ).shouldRequestAccess,
        isFalse,
      );
    });

    test('uses the Health App count even when it is lower than local cache',
        () {
      expect(
        resolveAppleHealthStepCount(healthSteps: 3200, localSteps: 4100),
        3200,
      );
    });

    test('keeps zero as a valid Health App count after the day resets', () {
      expect(
        resolveAppleHealthStepCount(healthSteps: 0, localSteps: 4100),
        0,
      );
    });

    test('uses Health App count when it is ahead of local cache', () {
      expect(
        resolveAppleHealthStepCount(
          healthSteps: 3250,
          localSteps: 3200,
        ),
        3250,
      );
    });
  });

  group('PendingStepSyncService', () {
    test('keeps highest pending count by default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await PendingStepSyncService.instance.queueStepProgress(
        userId: '42',
        date: '2026-07-31',
        stepCount: 4100,
        stepGoal: 5000,
        steps: true,
      );
      await PendingStepSyncService.instance.queueStepProgress(
        userId: '42',
        date: '2026-07-31',
        stepCount: 3200,
        stepGoal: 5000,
        steps: true,
      );

      final prefs = await SharedPreferences.getInstance();
      final pending = jsonDecode(prefs.getString('pending_step_syncs_42')!)
          as Map<String, dynamic>;

      expect(pending['2026-07-31']['step_count'], 4100);
    });

    test('can replace pending count for source-of-truth Health syncs',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await PendingStepSyncService.instance.queueStepProgress(
        userId: '42',
        date: '2026-07-31',
        stepCount: 4100,
        stepGoal: 5000,
        steps: true,
      );
      await PendingStepSyncService.instance.queueStepProgress(
        userId: '42',
        date: '2026-07-31',
        stepCount: 3200,
        stepGoal: 5000,
        steps: true,
        preferLatestStepCount: true,
      );

      final prefs = await SharedPreferences.getInstance();
      final pending = jsonDecode(prefs.getString('pending_step_syncs_42')!)
          as Map<String, dynamic>;

      expect(pending['2026-07-31']['step_count'], 3200);
    });
  });
}
