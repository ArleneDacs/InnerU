import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:selfcare_projects/src/constants/sizes.dart';
import 'package:selfcare_projects/src/constants/text_strings.dart'; // Ensure correct constants import

class ForgotPasswordMail extends StatefulWidget {
  const ForgotPasswordMail({Key? key}) : super(key: key);

  @override
  _ForgotPasswordMail createState() => _ForgotPasswordMail();
}

class _ForgotPasswordMail extends State<ForgotPasswordMail> {
  final TextEditingController _emailController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 150),

              // Title
              const Text(
                "Reset Password",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 40),

              // Form Fields
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    // Email TextField with Icon in prefixIcon
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(color: Colors.brown),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.brown),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.brown, width: 2),
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.mail,
                          size: 28,
                          color: Colors.brown,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          // Your logic for sending reset instructions goes here
                          // You can use Firebase or other services to send the email
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Password reset link sent to ${_emailController.text}')),
                          );
                        },
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

          // Bottom Image
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
