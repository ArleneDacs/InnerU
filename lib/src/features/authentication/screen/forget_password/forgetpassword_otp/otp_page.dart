import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgotpassword_mail/forgotpasswordmail.dart';

class OTPPage extends StatelessWidget {
  const OTPPage({super.key, required this.verificationId});

  final String verificationId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter OTP')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sms_failed_outlined, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Phone password reset is not supported yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use email reset instead.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordMail(),
                    ),
                  );
                },
                child: const Text('Use Email Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
