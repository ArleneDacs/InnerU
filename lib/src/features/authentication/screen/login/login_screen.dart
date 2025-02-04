import 'package:firebase_auth/firebase_auth.dart'; // Add Firebase Authentication import
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/constants/sizes.dart';
import 'package:selfcare_projects/src/constants/text_strings.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgetpassword_otp/forgotpasswordotp.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgotpassword_mail/forgotpasswordmail.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/signup.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart'; // Ensure correct import
import 'package:flutter/cupertino.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isPasswordVisible = false; // Add this to toggle password visibility
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>(); // Form key for validation

  // Validate credentials with Firebase Authentication
  Future<bool> _validateCredentials(String email, String password) async {
    try {
      // Use Firebase Authentication to sign in with email and password
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user != null;
    } on FirebaseAuthException catch (e) {
      // Handle errors such as wrong email/password
      if (e.code == 'user-not-found') {
        print('No user found for that email.');
      } else if (e.code == 'wrong-password') {
        print('Wrong password provided for that user.');
      }
      return false;
    }
  }

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
                "Selfcare",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 40),

              // Form Fields
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Form(
                  key: _formKey, // Assign the form key
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an email';
                          }
                          return null;
                        },
                        decoration: const InputDecoration(
                          labelText: "Email",
                          labelStyle: TextStyle(color: Colors.brown),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: "Password",
                          labelStyle: const TextStyle(color: Colors.brown),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.brown, width: 2),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? CupertinoIcons.eye_slash
                                  : CupertinoIcons.eye,
                              size: 28,
                              color: Colors.brown,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),

                      // Forgot Password Link
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                              ),
                              builder: (context) => Container(
                                padding: EdgeInsets.all(tDefaultSize),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tForgotPasswordTittle,
                                      style: Theme.of(context).textTheme.headlineMedium,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      tForgotPasswordSubTitle,
                                      style: Theme.of(context).textTheme.labelSmall ?? TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 20),
                                    // Email reset option
                                    Container(
                                      padding: const EdgeInsets.all(15.0),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10.0),
                                        color: Colors.grey.shade300,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => ForgotPasswordMail()),
                                          );
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(CupertinoIcons.mail, size: 28),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(tEmail, style: Theme.of(context).textTheme.bodyMedium),
                                                  Text(tResetViaEMail, style: Theme.of(context).textTheme.bodySmall),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    //phone reset options
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(15.0),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10.0),
                                        color: Colors.grey.shade300,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => ForgotPasswordOTP()),
                                          );
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(CupertinoIcons.device_phone_portrait, size: 28),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(tPhone, style: Theme.of(context).textTheme.bodyMedium),
                                                  Text(tResetViaPhone, style: Theme.of(context).textTheme.bodySmall),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            "Forgot Password?",
                            style: TextStyle(color: Colors.brown),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Login Button with validation
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
                          onPressed: () async {
                            if (_formKey.currentState?.validate() ?? false) {
                              String email = _emailController.text;
                              String password = _passwordController.text;

                              bool isValid = await _validateCredentials(email, password);

                              if (isValid) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DashboardScreen(),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Invalid credentials, please try again.')),
                                );
                              }
                            }
                          },
                          child: const Text(
                            "Log-in",
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      // Sign-up Navigation
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account?"),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SignupScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              "Sign up.",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 50),
                    ],
                  ),
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
