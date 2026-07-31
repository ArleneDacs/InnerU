import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/pending_step_sync_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class AppleHealthStepsService {
  AppleHealthStepsService._();

  static final AppleHealthStepsService instance = AppleHealthStepsService._();

  static const MethodChannel _channel = MethodChannel('inneru/apple_health');

  Future<int?> syncTodaySteps() async {
    if (kIsWeb || !Platform.isIOS) return null;

    final session = AuthService.instance.currentSession;
    final userId = session?.id.toString();
    if (userId == null || userId.isEmpty) return null;

    final healthSteps = await _readTodaySteps();
    if (healthSteps == null) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedStepsKey = SessionCleanupService.savedStepsKey(userId);
    final lastSavedDateKey = SessionCleanupService.lastSavedDateKey(userId);
    final dailyGoal = await _loadDailyGoal(userId, prefs);
    final lastSavedDate = prefs.getString(lastSavedDateKey);
    final localSteps =
        lastSavedDate == today ? prefs.getInt(savedStepsKey) ?? 0 : 0;
    final resolvedSteps = localSteps > healthSteps ? localSteps : healthSteps;

    await prefs.setInt(savedStepsKey, resolvedSteps);
    await prefs.setString(lastSavedDateKey, today);
    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
    WatchSyncService.instance.syncSteps(
      resolvedSteps,
      goal: dailyGoal,
      force: true,
    );

    unawaited(_syncToServer(
      userId: userId,
      date: today,
      steps: resolvedSteps,
      goal: dailyGoal,
      username: session?.name,
    ));

    return resolvedSteps;
  }

  Future<int?> _readTodaySteps() async {
    try {
      final result = await _channel.invokeMethod<int>('readTodaySteps');
      return result == null || result < 0 ? null : result;
    } on PlatformException catch (error) {
      debugPrint('Apple Health step sync unavailable: ${error.code}');
      return null;
    } catch (error) {
      debugPrint('Apple Health step sync failed: $error');
      return null;
    }
  }

  Future<int> _loadDailyGoal(String userId, SharedPreferences prefs) async {
    final cachedGoal = prefs.getInt('daily_step_goal_$userId');
    if (cachedGoal != null && cachedGoal > 0) {
      return cachedGoal;
    }

    try {
      final userData = await UserService.getUserData();
      final rawGoal = userData['daily_step_goal'] ?? userData['dailyStepGoal'];
      final goal = rawGoal is num ? rawGoal.toInt() : int.tryParse('$rawGoal');
      if (goal != null && goal > 0) {
        await prefs.setInt('daily_step_goal_$userId', goal);
        return goal;
      }
    } catch (error) {
      debugPrint('Apple Health daily goal load failed: $error');
    }

    return 5000;
  }

  Future<void> _syncToServer({
    required String userId,
    required String date,
    required int steps,
    required int goal,
    String? username,
  }) async {
    String? companyId;
    String? companyCode;
    String? companyName;

    try {
      await PendingStepSyncService.instance.flush(userId: userId);
      final membershipData = await CompanyMembershipService.loadForUser(userId);
      companyId = membershipData.activeMembership?.id;
      companyCode = membershipData.activeMembership?.code;
      companyName = membershipData.activeMembership?.name;
      await DailyTrackerApiService.instance.upsert(
        date: date,
        stepCount: steps,
        stepGoal: goal,
        steps: steps > 0,
        username: username,
        companyId: companyId,
        companyCode: companyCode,
        companyName: companyName,
      );
    } catch (error) {
      debugPrint('Apple Health step sync queued: $error');
      await PendingStepSyncService.instance.queueStepProgress(
        userId: userId,
        date: date,
        stepCount: steps,
        stepGoal: goal,
        steps: steps > 0,
        username: username,
        companyId: companyId,
        companyCode: companyCode,
        companyName: companyName,
      );
    }
  }
}
