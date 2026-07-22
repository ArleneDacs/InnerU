import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';

class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({super.key, required this.email});

  final String email;

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  bool _isResendDisabled = false;
  bool _isSending = false;
  int _countdown = 30;

  ActionCodeSettings get _verificationLinkSettings => const ActionCodeSettings(
        url: 'https://selfcare-1476e.firebaseapp.com/email-link-login',
        handleCodeInApp: false,
        androidPackageName: 'com.valenin.inneru',
        iOSBundleId: 'com.valenin.inneru',
        androidInstallApp: false,
        androidMinimumVersion: '21',
      );

  Future<void> _resendVerificationEmail() async {
    if (_isSending || _isResendDisabled) return;

    setState(() {
      _isSending = true;
    });

    _verificationLinkSettings;

    final error = await AuthService.sendVerificationEmail(email: widget.email);

    if (!mounted) return;

    setState(() {
      _isSending = false;
      _isResendDisabled = true;
      _countdown = 30;
    });

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isResendDisabled = false;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verification email sent. Please check your inbox.'),
      ),
    );

    while (mounted && _countdown > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (_countdown == 1) {
        setState(() {
          _countdown = 0;
          _isResendDisabled = false;
        });
      } else {
        setState(() {
          _countdown -= 1;
        });
      }
    }
  }

  Future<void> _backToLogin() async {
    await SessionCleanupService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 84,
                    color: Color(0xFF4C6B43),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to ${widget.email}. Please verify your email before signing in.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _isResendDisabled || _isSending ? null : _resendVerificationEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4C6B43),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isResendDisabled
                                  ? 'Resend in $_countdown s'
                                  : 'Resend verification email',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _backToLogin,
                    child: const Text('Back to login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
