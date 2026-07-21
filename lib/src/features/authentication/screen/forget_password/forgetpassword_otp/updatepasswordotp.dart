import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgotpassword_mail/forgotpasswordmail.dart';

class UpdatePasswordOTP extends StatelessWidget {
  const UpdatePasswordOTP({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update Password')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Phone password reset is not supported yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
