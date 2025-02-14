import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePass extends StatefulWidget {
  const ChangePass({super.key, required this.title});
  final String title;

  @override
  State<ChangePass> createState() => _ChangePass();
}

class _ChangePass extends State<ChangePass> {
  final TextEditingController _emailController = TextEditingController();
  bool _isEmailFormatCorrect = true;
  bool _isEmailExist = false;
  bool _isCheckingEmail = false;
  bool _isButtonEnabled = false;
  bool _isLoading = false;

  bool _isEmailFormatValid(String email) {
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
    RegExp regExp = RegExp(emailPattern);
    return regExp.hasMatch(email);
  }

  Future<void> _checkEmailAvailability(String email) async {
    setState(() {
      _isCheckingEmail = true;
      _isButtonEnabled = false;
    });

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    setState(() {
      _isEmailExist = querySnapshot.docs.isNotEmpty;
      _isCheckingEmail = false;
      _isButtonEnabled = _isEmailExist;
    });

    if (!_isEmailExist) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("This email does not exist in the system."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    setState(() {
      _isLoading = true;
      _isButtonEnabled = false;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Password reset link sent to your email."),
          backgroundColor: Colors.green,
        ),
      );

      _emailController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                      _isEmailExist = false;
                      _isButtonEnabled = false;
                    });

                    if (isValidFormat) {
                      _checkEmailAvailability(value);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: "Enter your email",
                    filled: true,
                    fillColor: Color(0xFFffecc9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.all(12),
                    errorText: _isEmailFormatCorrect ? null : "Invalid email format",
                  ),
                ),
              ),
               SizedBox(height: 70.0),
              ElevatedButton(
                onPressed: _isButtonEnabled ? _sendPasswordResetEmail : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isButtonEnabled ? Color(0xFFce8f5a) : Colors.grey,
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
