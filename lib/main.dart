import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/firebase_options.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_dashboard.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/admin_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/manage_companies.dart';
import 'package:selfcare_projects/src/features/authentication/screen/auth/auth_role_home.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coaches/coaches_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/community/community_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/today_intake_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/daily_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/fasting_tracker/fasting_report_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/fasting_tracker/fasting_timer_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_settings.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/splash_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/email_link_auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';
import 'package:selfcare_projects/src/services/step_background_service.dart';
import 'package:selfcare_projects/src/services/watch_steps_receiver.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AuthService.instance.initialize();
  await FastingNotificationService.instance.initialize();
  await StepBackgroundService.instance.configure();
  WatchStepsReceiver.instance.start();

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => TimeProvider(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        builder: (context, child) => _ResponsiveAppShell(
          child: child ?? const SizedBox.shrink(),
        ),
        home: GlobalPaddingWrapper(
          child: SplashScreen(),
        ),
        routes: {
          '/home': (context) => DashboardScreen(),
          '/leaderboard': (context) => _companyThemed(const Leaderboard()),
          '/meditation': (context) => Meditation(),
          '/notes': (context) => Notes(),
          '/stepTracker': (context) => StepTracker(),
          '/exerciseTracker': (context) => const ExerciseTrackerScreen(),
          // '/noteGallery': (context) => NotesGallery(),
          '/sleepTracker': (context) => _companyThemed(SleepTracker()),
          '/coachesScreen': (context) => CoachesScreen(),
          '/admin': (context) => const AdminDashboardScreen(),
          '/adminProfile': (context) => const AdminProfileScreen(),
          '/adminCompanies': (context) => const ManageCompaniesScreen(),
          '/emotionScreen': (context) => _companyThemed(EmotionTrackerPage()),
          '/goalsHub': (context) => _companyThemed(const GoalsHubScreen()),
          '/userprogress': (context) =>
              _companyThemed(const UserProgressPage()),
          '/communityScreen': (context) => CommunityScreen(),
          '/calorieTracker': (context) =>
              _companyThemed(const CalorieTrackerScreen()),
          '/todayIntake': (context) =>
              _companyThemed(const TodayIntakeScreen()),
          '/fastingTimer': (context) =>
              _companyThemed(const FastingTimerScreen()),
          '/fastingReports': (context) =>
              _companyThemed(const FastingReportScreen()),
          '/profileSettings': (context) => ProfileSettings(),
          '/todolist': (context) => _companyThemed(const TodoList()),
          '/login': (context) => LoginScreen(),
          '/meditationSong': (context) => MeditationSong(),
          'notesType': (context) => NotesType(
                  note: Note(
                username: '',
                id: '',
                title: '',
                note: [],
                createdAt: DateTime.now(),
                category: '',
                userId: '',
              )),
          '/profile': (context) => ProfilePage(
                title: '',
              )
        },
      ),
    );
  }
}

Widget _companyThemed(Widget child) {
  return CompanyThemeBuilder(
    builder: (context, companyTheme) {
      return Theme(
        data: AppTheme.company(companyTheme),
        child: child,
      );
    },
  );
}

class _ResponsiveAppShell extends StatelessWidget {
  const _ResponsiveAppShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
        ),
      ),
      child: child,
    );
  }
}

class GlobalPaddingWrapper extends StatefulWidget {
  final Widget child;
  const GlobalPaddingWrapper({super.key, required this.child});

  @override
  State<GlobalPaddingWrapper> createState() => _GlobalPaddingWrapperState();
}

class _GlobalPaddingWrapperState extends State<GlobalPaddingWrapper> {
  String? _lastSeenUserId;

  @override
  void initState() {
    super.initState();
    unawaited(
      EmailLinkAuthService.instance.init(navigatorKey: appNavigatorKey),
    );
  }

  @override
  void dispose() {
    unawaited(EmailLinkAuthService.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppSession?>(
      stream: AuthService.instance.sessionStream,
      initialData: AuthService.instance.currentSession,
      builder: (context, snapshot) {
        final currentUserId = snapshot.data?.id.toString();
        final previousUserId = _lastSeenUserId;
        if (previousUserId != currentUserId) {
          _lastSeenUserId = currentUserId;
          if (previousUserId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              context.read<TimeProvider>().resetForAccountSwitch();
              unawaited(
                SessionCleanupService.clearLocalSession(userId: previousUserId),
              );
            });
          }
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const AuthRoleHome();
        }
        return widget.child;
      },
    );
  }
}
