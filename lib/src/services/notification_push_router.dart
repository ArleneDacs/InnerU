import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_step_submissions_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/my_accountability_meetings_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/community/community_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notifications/notifications_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/my_step_submissions_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/notification_api_service.dart';

class NotificationPushRouter {
  NotificationPushRouter._();

  static final NotificationPushRouter instance = NotificationPushRouter._();

  GlobalKey<NavigatorState>? _navigatorKey;

  void configure(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  Future<void> handlePushTap(Map<String, dynamic> notification) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    final notificationId =
        (notification['notification_id'] as String?)?.trim() ??
            (notification['id'] as String?)?.trim() ??
            '';
    if (notificationId.isNotEmpty) {
      unawaited(NotificationApiService.instance.markRead(notificationId));
    }

    final type = (notification['type'] as String?)?.trim() ?? '';
    final data = notification['data'];

    switch (type) {
      case 'mentee_request_accepted':
      case 'added_to_group':
        navigator.pushNamed('/coachesScreen');
        return;
      case 'streak_milestone':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => MeditationStreakRewardsScreen(
              activityType: _activityStreakTypeFromLabel(
                data is Map ? data['activity'] as String? : null,
              ),
            ),
          ),
        );
        return;
      case 'community_comment':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const CommunityScreen(),
          ),
        );
        return;
      case 'step_submission_approved':
      case 'step_submission_declined':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const MyStepSubmissionsScreen(),
          ),
        );
        return;
      case 'meeting_reminder_day_before':
      case 'meeting_reminder_day_of':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const MyAccountabilityMeetingsScreen(),
          ),
        );
        return;
      case 'mentee_request_received':
      case 'mentee_progress_logged':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const CoachDashboardScreen(),
          ),
        );
        return;
      case 'step_submission_received':
        navigator.push(
          MaterialPageRoute(
            builder: (context) => const CoachStepSubmissionsScreen(),
          ),
        );
        return;
      default:
        break;
    }

    final currentUserId = AuthService.instance.currentUserId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) => NotificationsScreen(userId: currentUserId),
        ),
      );
    }
  }

  ActivityStreakType _activityStreakTypeFromLabel(String? label) {
    switch (label) {
      case 'Steps':
        return ActivityStreakType.steps;
      case 'Exercise':
        return ActivityStreakType.exercise;
      case 'Fasting':
        return ActivityStreakType.fasting;
      case 'Meditation':
      default:
        return ActivityStreakType.meditation;
    }
  }
}
