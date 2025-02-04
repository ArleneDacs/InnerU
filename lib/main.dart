import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/firebase_options.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/splash_screen.dart';
import 'package:selfcare_projects/src/utils/theme/theme.dart';

void main() async {
  // Ensure that Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: TAppTheme.lightTheme,
      darkTheme: TAppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: SplashScreen(),
    );
  }
}
