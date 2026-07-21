import 'dart:async';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';

class CheckEmailScreen extends StatefulWidget {
  final String email;

  const CheckEmailScreen({super.key, required this.email});

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  bool _isResendDisabled = false;
  int _countdown = 30; // Start countdown from 30 seconds
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Email-link login is no longer available. Use email and password.",
        ),
      ),
    );
  }

  @override
  void dispose() {
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
              "Email-link login is unavailable",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Use your email and password to sign in for ${widget.email}.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isResendDisabled ? null : _resendLoginLink,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isResendDisabled ? Colors.grey : Color(0xFFCE8F5A),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: Text(_isResendDisabled
                  ? "Wait $_countdown s"
                  : "Try Again"),
            ),
            const SizedBox(height: 15),
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await SessionCleanupService.signOut();
                if (!mounted) return;
                navigator.pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text("Use a different email"),
            ),
          ],
        ),
      ),
    );
  }
}
