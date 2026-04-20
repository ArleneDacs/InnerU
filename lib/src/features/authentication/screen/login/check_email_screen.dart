import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/services/email_link_auth_service.dart';

class CheckEmailScreen extends StatefulWidget {
  final String email;

  const CheckEmailScreen({super.key, required this.email});

  @override
  _CheckEmailScreenState createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  bool _isResendDisabled = false;
  int _countdown = 30; // Start countdown from 30 seconds
  Timer? _authCheckTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    EmailLinkAuthService.instance.savePendingEmail(widget.email);
    _startAuthListener();
  }

  void _startAuthListener() {
    _authCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      User? user = FirebaseAuth.instance.currentUser;
      await user?.reload(); // Refresh user state
      if (user != null) {
        timer.cancel();
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Setuppage()),
          );
        }
      }
    });
  }

  void _startCountdown() {
    setState(() {
      _isResendDisabled = true;
      _countdown = 30; // Reset countdown to 30s
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        timer.cancel();
        setState(() => _isResendDisabled = false);
      }
    });
  }

  Future<void> _resendLoginLink() async {
    _startCountdown();

    try {
      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: widget.email,
        actionCodeSettings: ActionCodeSettings(
          url: EmailLinkAuthService.continueUrl,
          handleCodeInApp: true,
          androidPackageName: 'com.example.selfcare_projects',
          androidInstallApp: false,
          androidMinimumVersion: '21',
          iOSBundleId: 'com.example.selfcareProjects',
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Login link resent! Check your email."),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending login link: $e")),
      );
    }
  }

  @override
  void dispose() {
    _authCheckTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.email, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "Check Your Email",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "We've sent a login link to ${widget.email}. Click the link to continue.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
            onPressed: _isResendDisabled ? null : _resendLoginLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isResendDisabled ? Colors.grey : Color(0xFFCE8F5A), 
              foregroundColor: Colors.white, 
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), 
            ),
            child: Text(_isResendDisabled ? "Wait $_countdown s to Resend" : "Resend Login Link"),
          ),

            const SizedBox(height: 15),
            TextButton(
              onPressed: () {
                FirebaseAuth.instance.signOut().then((_) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                });
              },
              child: const Text("Use a different email"),
            ),
          ],
        ),
      ),
    );
  }
}
