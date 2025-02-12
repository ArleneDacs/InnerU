import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/firebase_options.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_gallery.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/splash_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/utils/theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
 await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => TimeProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            textTheme: TextTheme(
                titleLarge: GoogleFonts.parisienne(fontSize: 40),
                bodyMedium: GoogleFonts.puritan(
                    color: const Color.fromARGB(255, 60, 60, 60)))),
        darkTheme: TAppTheme.darkTheme,
        themeMode: ThemeMode.system,
      home: GlobalPaddingWrapper(
        child: SplashScreen(),
      ),
        routes: {
          '/home': (context) => DashboardScreen(),
          '/leaderboard': (context) => Leaderboard(),
          '/meditation': (context) => Meditation(),
          '/notes': (context) => Notes(),
          '/stepTracker': (context) => StepTracker(),
          '/noteGallery': (context) => NotesGallery(),
          'notesType': (context) => NotesType(
              note: Note(
                  username: '',
                  id: '',
                  title: '',
                  note: '',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now())),
          '/profile': (context) => ProfilePage(
                title: '',
              )
        },
      ),
    );
  }
}

class GlobalPaddingWrapper extends StatelessWidget {
  final Widget child;
  const GlobalPaddingWrapper({required this.child});
@override
Widget build(BuildContext context) {
  return StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasData && snapshot.data != null) {
        return CurvedNavBar(); 
      }
      return Padding(
        padding: const EdgeInsets.all(16.0), 
        child: SplashScreen(), 
      );
    },
  );
}

}
