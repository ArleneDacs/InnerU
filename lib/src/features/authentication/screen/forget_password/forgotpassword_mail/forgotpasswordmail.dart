import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/password_reset_api_service.dart';

class ForgotPasswordMail extends StatefulWidget {
  const ForgotPasswordMail({super.key});

  @override
  State<ForgotPasswordMail> createState() => _ForgotPasswordMailState();
}

class _ForgotPasswordMailState extends State<ForgotPasswordMail> {
  final TextEditingController _emailController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    String email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address.';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      await PasswordResetApiService.instance.sendResetLink(email);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Email Sent'),
          content: Text('A password reset link has been sent to $email'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Navigate back to login page
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      String errorMessage = 'An error occurred. Please try again.';
      if (!mounted) return;
      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.black;
    final labelColor = Colors.brown;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 150),
              Text(
                "Reset Password",
                style: TextStyle(
                    fontSize: 28,
                    color: textColor),
              ),
              const SizedBox(height: 40),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(color: labelColor),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: labelColor),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: labelColor, width: 2),
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.mail,
                          size: 28,
                          color: labelColor,
                        ),
                      ),
                    ),
                    if (_errorMessage !=
                        null) // Display error message if it exists
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red, fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _resetPassword,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "Reset Password",
                                style:
                                    TextStyle(fontSize: 18, color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Image.asset(
                "assets/images/login-image/login.png",
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
