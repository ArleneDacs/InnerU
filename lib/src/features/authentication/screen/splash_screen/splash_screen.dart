import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/constants/image_strings.dart';
import 'package:selfcare_projects/src/constants/text_strings.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Navigate to LoginScreen after 6 seconds
    Timer(Duration(seconds: 6), navigateToLogin);
  }

  void navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              tSplashTopIcon,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              fit: BoxFit.cover,
            ),
          ),


          // Continue Button
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Center(
              child: ElevatedButton(
                onPressed: navigateToLogin,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 10),
                  backgroundColor: Colors.green.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  "Continue",
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
