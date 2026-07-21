import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/password_reset_api_service.dart';

class ChangePass extends StatefulWidget {
  const ChangePass({super.key, required this.title});
  final String title;

  @override
  State<ChangePass> createState() => _ChangePass();
}

class _ChangePass extends State<ChangePass> {
  final TextEditingController _emailController = TextEditingController();
  bool _isEmailFormatCorrect = true;
  bool _isButtonEnabled = false;
  bool _isLoading = false;
  String? _successMessage;

  bool _isEmailFormatValid(String email) {
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
    RegExp regExp = RegExp(emailPattern);
    return regExp.hasMatch(email);
  }

  Future<void> _checkEmailAvailability(String email) async {
    setState(() {
      _isButtonEnabled = true;
    });
  }

  Future<void> _sendPasswordResetEmail() async {
    setState(() {
      _isLoading = true;
      _isButtonEnabled = false;
      _successMessage = null;
    });

    try {
      await PasswordResetApiService.instance.sendResetLink(
        _emailController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _successMessage = 'Password reset link sent to your email.';
        _emailController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(height: 225.0),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: TextField(
                  controller: _emailController,
                  onChanged: (value) {
                    bool isValidFormat = _isEmailFormatValid(value);

                    setState(() {
                      _isEmailFormatCorrect = isValidFormat;
                      _isButtonEnabled = isValidFormat;
                    });

                    if (isValidFormat) _checkEmailAvailability(value);
                  },
                  decoration: InputDecoration(
                    hintText: "Enter your email",
                    filled: true,
                    fillColor: Colors.amber.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.all(12),
                    errorText:
                        _isEmailFormatCorrect ? null : "Invalid email format",
                  ),
                ),
              ),
              if (_successMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _successMessage!,
                  style: const TextStyle(color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: 70.0),
              ElevatedButton(
                onPressed: _isButtonEnabled ? _sendPasswordResetEmail : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isButtonEnabled ? Colors.deepOrange : Colors.grey,
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Forgot Password',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
