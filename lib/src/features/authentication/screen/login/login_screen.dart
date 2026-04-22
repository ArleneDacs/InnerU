import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/auth/auth_role_home.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgetpassword_otp/forgotpasswordotp.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgotpassword_mail/forgotpasswordmail.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/role_selection_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';
import 'package:flutter/cupertino.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _loginError;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user != null) {
        await user.reload();
        user = FirebaseAuth.instance.currentUser;

        if (user!.emailVerified) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AuthRoleHome()),
          );
        } else {
          _showEmailNotVerifiedDialog(user);
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Login failed. Wrong Email or Password";
      if (e.code == 'user-not-found') {
        errorMessage = "No user found with this email.";
      } else if (e.code == 'wrong-password') {
        errorMessage = "Incorrect password.";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Invalid email format.";
      }

      setState(() {
        _loginError = errorMessage;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showEmailNotVerifiedDialog(User user) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Email Not Verified"),
          content: const Text(
              "Your email is not verified. Please verify before logging in."),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  await user.sendEmailVerification();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Verification email sent."),
                        backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Error sending verification email."),
                        backgroundColor: Colors.red),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text("Resend Email"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  void _showForgotPasswordOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Reset Password",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text("Choose how you want to reset your password:"),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.email, color: Colors.blue),
                title: const Text("Reset via Email"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ForgotPasswordMail()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.phone, color: Colors.green),
                title: const Text("Reset via Phone"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ForgotPasswordOTP()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    final error = await AuthService().signInWithGoogle();

    if (!mounted) return;

    if (error == AuthService.userCancelledGoogleFlow) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (error == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthRoleHome()),
      );
      return;
    } else {
      setState(() {
        _loginError = error;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final verticalTopSpace = context.screenHeight * 0.1;
    final heroBottomInset = context.isTabletWidth ? 80.0 : 24.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: heroBottomInset),
              child: Image.asset(
                "assets/images/login-image/login.png",
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
              ),
              child: ResponsiveContent(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: verticalTopSpace.clamp(32, 90)),

                      if (_loginError != null)
                        Container(
                          padding: EdgeInsets.all(context.responsiveValue(12)),
                          margin: EdgeInsets.only(
                            bottom: context.responsiveValue(20),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _loginError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _loginError = null;
                                  });
                                },
                              )
                            ],
                          ),
                        ),

                      Text(
                        "Selfcare",
                        style: TextStyle(
                          fontSize: context.responsiveFont(35),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Parisienne',
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(36)),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: "Email"),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Enter your email";
                          }
                          if (!RegExp(
                                  r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
                              .hasMatch(value)) {
                            return "Enter a valid email";
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(15)),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: "Password",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible
                                  ? CupertinoIcons.eye_slash
                                  : CupertinoIcons.eye,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordOptions,
                          child: const Text("Forgot Password?"),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(20)),
                      SizedBox(
                        width: double.infinity,
                        height: context.responsiveValue(50, min: 0.95, max: 1.05),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            backgroundColor:
                                const Color.fromARGB(255, 89, 189, 179),
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  "Log-in",
                                  style: TextStyle(
                                    fontSize: context.responsiveFont(12),
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(20)),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(
                              color: Color.fromARGB(255, 91, 195, 183),
                              thickness: 1,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text("OR"),
                          ),
                          const Expanded(
                            child: Divider(
                              color: Color.fromARGB(255, 91, 195, 183),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsiveValue(20)),
                      GestureDetector(
                        onTap: _isLoading ? null : _handleGoogleLogin,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            vertical: context.responsiveValue(12),
                            horizontal: context.responsiveValue(20),
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.5),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              Image.asset(
                                "assets/logo/google.png",
                                width: context.responsiveValue(30),
                              ),
                              Text(
                                "Sign in with Google",
                                style: TextStyle(
                                  fontSize: context.responsiveFont(16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(30)),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text("Don't have an account?"),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const RoleSelectionScreen(),
                                ),
                              );
                            },
                            child: const Text("Sign up."),
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsiveValue(24)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
