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

enum AppleHealthStepSyncStatus {
  success,
  skipped,
  permissionDenied,
  unavailable,
  accessMayBeDisabled,
  queryFailed,
}

class AppleHealthStepSyncResult {
  const AppleHealthStepSyncResult({
    required this.status,
    this.steps,
  });

  final AppleHealthStepSyncStatus status;
  final int? steps;

  bool get shouldRequestAccess =>
      status == AppleHealthStepSyncStatus.permissionDenied ||
      status == AppleHealthStepSyncStatus.unavailable ||
      status == AppleHealthStepSyncStatus.accessMayBeDisabled;
}

class AppleHealthStepsService {
  AppleHealthStepsService._();

  static final AppleHealthStepsService instance = AppleHealthStepsService._();

  static const MethodChannel _channel = MethodChannel('inneru/apple_health');
  static const Duration _errorLogThrottle = Duration(seconds: 30);

  DateTime? _lastErrorLoggedAt;
  String? _lastErrorCode;

  Future<int?> syncTodaySteps() async {
    final result = await checkTodaySteps();
    return result.steps;
  }

  Future<bool> requestStepsAccess() async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('requestStepsAccess');
      return result == true;
    } on PlatformException catch (error) {
      _logSyncError(
        'Apple Health access request failed: ${error.code}'
        '${error.message == null ? '' : ' - ${error.message}'}',
      );
      return false;
    } catch (error) {
      _logSyncError('Apple Health access request failed: $error');
      return false;
    }
  }

  Future<bool> openHealthApp() async {
    if (kIsWeb || !Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod<bool>('openHealthApp');
      return result == true;
    } on PlatformException catch (error) {
      _logSyncError(
        'Apple Health app open failed: ${error.code}'
        '${error.message == null ? '' : ' - ${error.message}'}',
      );
      return false;
    } catch (error) {
      _logSyncError('Apple Health app open failed: $error');
      return false;
    }
  }

  Future<AppleHealthStepSyncResult> checkTodaySteps() async {
    if (kIsWeb || !Platform.isIOS) {
      return const AppleHealthStepSyncResult(
        status: AppleHealthStepSyncStatus.skipped,
      );
    }

    final session = AuthService.instance.currentSession;
    final userId = session?.id.toString();
    if (userId == null || userId.isEmpty) {
      return const AppleHealthStepSyncResult(
        status: AppleHealthStepSyncStatus.skipped,
      );
    }

    final healthRead = await _readTodaySteps();
    final healthSteps = healthRead.steps;
    if (healthSteps == null) {
      return AppleHealthStepSyncResult(status: healthRead.status);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedStepsKey = SessionCleanupService.savedStepsKey(userId);
    final lastSavedDateKey = SessionCleanupService.lastSavedDateKey(userId);
    final lastReadableHealthStepsKey =
        SessionCleanupService.appleHealthLastReadableStepsKey(userId);
    final dailyGoal = await _loadDailyGoal(userId, prefs);
    final lastSavedDate = prefs.getString(lastSavedDateKey);
    final lastReadableHealthSteps =
        prefs.getInt(lastReadableHealthStepsKey) ?? 0;
    final localSteps =
        lastSavedDate == today ? prefs.getInt(savedStepsKey) ?? 0 : 0;
    if (healthSteps == 0 && (localSteps > 0 || lastReadableHealthSteps > 0)) {
      return const AppleHealthStepSyncResult(
        status: AppleHealthStepSyncStatus.accessMayBeDisabled,
      );
    }
    final resolvedSteps = resolveAppleHealthStepCount(
      healthSteps: healthSteps,
      localSteps: localSteps,
    );

    await prefs.setInt(savedStepsKey, resolvedSteps);
    await prefs.setString(lastSavedDateKey, today);
    await prefs.setString(SessionCleanupService.stepCacheOwnerKey, userId);
    if (healthSteps > 0) {
      await prefs.setInt(lastReadableHealthStepsKey, healthSteps);
    }
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

    return AppleHealthStepSyncResult(
      status: AppleHealthStepSyncStatus.success,
      steps: resolvedSteps,
    );
  }

  Future<AppleHealthStepSyncResult> _readTodaySteps() async {
    try {
      final result = await _channel.invokeMethod<int>('readTodaySteps');
      if (result == null || result < 0) {
        return const AppleHealthStepSyncResult(
          status: AppleHealthStepSyncStatus.queryFailed,
        );
      }
      return AppleHealthStepSyncResult(
        status: AppleHealthStepSyncStatus.success,
        steps: result,
      );
    } on PlatformException catch (error) {
      _logSyncError(
        'Apple Health step sync unavailable: ${error.code}'
        '${error.message == null ? '' : ' - ${error.message}'}',
      );
      return AppleHealthStepSyncResult(
        status: _statusForPlatformException(error),
      );
    } catch (error) {
      _logSyncError('Apple Health step sync failed: $error');
      return const AppleHealthStepSyncResult(
        status: AppleHealthStepSyncStatus.queryFailed,
      );
    }
  }

  void _logSyncError(String message) {
    final now = DateTime.now();
    if (_lastErrorCode == message &&
        _lastErrorLoggedAt != null &&
        now.difference(_lastErrorLoggedAt!) < _errorLogThrottle) {
      return;
    }

    _lastErrorCode = message;
    _lastErrorLoggedAt = now;
    debugPrint(message);
  }

  AppleHealthStepSyncStatus _statusForPlatformException(
    PlatformException error,
  ) {
    return switch (error.code) {
      'HEALTH_PERMISSION_DENIED' => AppleHealthStepSyncStatus.permissionDenied,
      'HEALTH_UNAVAILABLE' => AppleHealthStepSyncStatus.unavailable,
      _ => AppleHealthStepSyncStatus.queryFailed,
    };
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
      await DailyTrackerApiService.instance.recordCompletedActivities(
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
        preferLatestStepCount: true,
      );
    }
  }
}

@visibleForTesting
int resolveAppleHealthStepCount({
  required int healthSteps,
  required int localSteps,
}) {
  return healthSteps;
}
