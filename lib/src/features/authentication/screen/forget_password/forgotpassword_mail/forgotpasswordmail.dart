import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore

class ForgotPasswordMail extends StatefulWidget {
  const ForgotPasswordMail({Key? key}) : super(key: key);

  @override
  _ForgotPasswordMailState createState() => _ForgotPasswordMailState();
}

class _ForgotPasswordMailState extends State<ForgotPasswordMail> {
  final TextEditingController _emailController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _errorMessage; // To hold the error message

  Future<void> _resetPassword() async {
    String email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email address.';
      });
      return;
    }

    try {
      // Check if the email exists in Firestore
      QuerySnapshot querySnapshot = await _firestore
          .collection('users') // Change to your actual collection name
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // Email not found in Firestore
        setState(() {
          _errorMessage = 'Email is not registered.';
        });
        return;
      }

      // Send reset password email
      await _auth.sendPasswordResetEmail(email: email);
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
      if (e is FirebaseAuthException) {
        if (e.code == 'invalid-email') {
          errorMessage =
              'Invalid email format. Please enter a valid email address.';
        }
      }
      setState(() {
        _errorMessage = errorMessage; // Update the error message
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color labelColor = isDarkMode ? Colors.grey[300]! : Colors.brown;

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
                    fontWeight: FontWeight.bold,
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
                          backgroundColor:
                              const Color.fromARGB(255, 89, 189, 179),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _resetPassword,
                        child: const Text(
                          "Reset Password",
                          style: TextStyle(fontSize: 18, color: Colors.white),
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
