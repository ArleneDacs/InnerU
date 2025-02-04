import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:selfcare_projects/src/constants/sizes.dart';
import 'package:selfcare_projects/src/constants/text_strings.dart'; // Ensure correct constants import

class ForgotPasswordOTP extends StatefulWidget {
  const ForgotPasswordOTP({Key? key}) : super(key: key);

  @override
  _ForgotPasswordOTP createState() => _ForgotPasswordOTP();
}

class _ForgotPasswordOTP extends State<ForgotPasswordOTP> {
  final TextEditingController _phoneController = TextEditingController();

  bool _isOTPSent = false;

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
                    // Phone Number TextField
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone Number",
                        labelStyle: TextStyle(color: Colors.brown),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.brown),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.brown, width: 2),
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.device_phone_portrait,
                          size: 28,
                          color: Colors.brown,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // OTP Button (Only shown after phone number input)
                    if (!_isOTPSent)
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
                            // Your logic for sending OTP goes here
                            // Example: Send OTP through Firebase or custom service
                            setState(() {
                              _isOTPSent = true; // Indicate OTP is sent
                            });

                            // Show Snackbar or other success indication
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('OTP sent to ${_phoneController.text}')),
                            );
                          },
                          child: const Text(
                            "Send OTP",
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                        ),
                      ),

                    // OTP TextField (Only shown after OTP is sent)
                    if (_isOTPSent)
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: "Enter OTP",
                          labelStyle: TextStyle(color: Colors.brown),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown, width: 2),
                          ),
                          prefixIcon: Icon(
                            CupertinoIcons.lock,
                            size: 28,
                            color: Colors.brown,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Verify OTP Button (Only shown after OTP is sent)
                    if (_isOTPSent)
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
                            // Your OTP verification logic goes here
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('OTP Verified, proceed to reset password.')),
                            );

                            // Navigate to password reset screen
                            // Navigator.push(context, MaterialPageRoute(builder: (context) => ResetPasswordScreen()));
                          },
                          child: const Text(
                            "Verify OTP",
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
