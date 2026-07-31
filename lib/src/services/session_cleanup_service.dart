import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_map_tracker_screen.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/pending_step_sync_service.dart';
import 'package:selfcare_projects/src/services/spotify_native_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionCleanupService {
  static const String stepCacheOwnerKey = 'step_cache_owner_uid';

  static String savedStepsKey(String userId) => 'saved_steps_$userId';
  static String initialStepsKey(String userId) => 'initial_steps_$userId';
  static String stepOffsetKey(String userId) => 'step_offset_$userId';
  static String lastSavedDateKey(String userId) => 'last_saved_date_$userId';
  static String appleHealthLastSyncedAtKey(String userId) =>
      'apple_health_last_synced_at_$userId';
  static String appleHealthLastReadableStepsKey(String userId) =>
      'apple_health_last_readable_steps_$userId';

  static Future<void> clearLocalSession({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('saved_steps');
    await prefs.remove('initial_steps');
    await prefs.remove('step_offset');
    await prefs.remove('last_saved_date');
    await prefs.remove('username');
    await prefs.remove('sleep_tracker_mode');
    await prefs.remove('sleep_tracker_goal_hours');
    await prefs.remove('sleep_tracker_bedtime_hour');
    await prefs.remove('sleep_tracker_bedtime_minute');
    await prefs.remove('sleep_tracker_active_start');
    await prefs.remove('sleep_tracker_history');
    await prefs.remove(stepCacheOwnerKey);

    if (userId != null && userId.isNotEmpty) {
      await prefs.remove(savedStepsKey(userId));
      await prefs.remove(initialStepsKey(userId));
      await prefs.remove(stepOffsetKey(userId));
      await prefs.remove(lastSavedDateKey(userId));
      await prefs.remove(appleHealthLastSyncedAtKey(userId));
      await prefs.remove(appleHealthLastReadableStepsKey(userId));
      await PendingStepSyncService.instance.clearForUser(userId);
    }

    await AudioHelper.stopAudio();
    await SpotifyNativeService.instance.stop();
    await FastingNotificationService.instance.cancelDailySleepBedtimeReminder();
    await FastingNotificationService.instance.cancelSleepWakeNotification();
    await FastingNotificationService.instance.cancelSleepOngoingNotification();
    await FastingNotificationService.instance
        .cancelExerciseCompleteNotification();
    FlutterBackgroundService().invoke('stopService');
    await clearStepMapTrackerStateForSignOut();
  }

  static Future<void> signOut({GoogleSignIn? googleSignIn}) async {
    final userId = AuthService.instance.currentSession?.id.toString();

    await clearLocalSession(userId: userId);
    await AuthService.instance.signOutGoogle();
    await googleSignIn?.signOut();
  }
}
