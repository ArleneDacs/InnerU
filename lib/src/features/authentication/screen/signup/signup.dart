import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.selectedRole,
  });

  final String selectedRole;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _retypepassController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhoneNumber(String number) {
    final phoneRegex = RegExp(r'^[0-9]{10,15}$');
    return phoneRegex.hasMatch(number);
  }

  bool _isValidPassword(String password) {
    final passwordRegex = RegExp(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d).{8,}$');
    return passwordRegex.hasMatch(password);
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final error = await AuthService().signUpUser(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      number: _numberController.text.trim(),
      retypepassword: _retypepassController.text.trim(),
      role: widget.selectedRole,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (error == null) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Verify Your Email"),
            content: Text(
              "A verification email has been sent. Please check your email and verify your ${widget.selectedRole} account.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _numberController.dispose();
    _retypepassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final topSpacing = context.screenHeight * 0.12;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              "assets/images/login-image/signup.png",
              fit: BoxFit.cover,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: topSpacing.clamp(72, 130)),
                      Text(
                        "Create an Account",
                        style: TextStyle(
                          fontSize: context.responsiveFont(26),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Parisienne',
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(14)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.responsiveValue(14),
                          vertical: context.responsiveValue(10),
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F6F3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF59BDB3).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              CupertinoIcons.person_crop_circle_badge_checkmark,
                              color: Color(0xFF3E9189),
                              size: 18,
                            ),
                            SizedBox(width: context.responsiveValue(8)),
                            Text(
                              "Selected role: ${widget.selectedRole == 'coach' ? 'Coach' : 'User'}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF245A55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(18)),
                      TextFormField(
                        controller: _usernameController,
                        maxLength: 20,
                        decoration: const InputDecoration(
                          labelText: "Username",
                          counterText: "",
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Username cannot be empty";
                          }
                          if (value.length > 20) {
                            return "Username must be at most 20 characters";
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: "Email"),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Email cannot be empty";
                          }
                          if (!_isValidEmail(value)) {
                            return "Invalid email format!";
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      TextFormField(
                        controller: _numberController,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: "Phone Number"),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Phone number cannot be empty";
                          }
                          if (!_isValidPhoneNumber(value)) {
                            return "Invalid phone number!";
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(10)),
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
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Password cannot be empty.";
                          }
                          if (!_isValidPassword(value)) {
                            return "Weak password! Use upper, lower, digit and 8+ chars.";
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      TextFormField(
                        controller: _retypepassController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: "Re-type Password",
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
                        validator: (value) => value != _passwordController.text
                            ? "Passwords do not match!"
                            : null,
                      ),
                      SizedBox(height: context.responsiveValue(25)),
                      SizedBox(
                        width: double.infinity,
                        height:
                            context.responsiveValue(50, min: 0.95, max: 1.05),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            backgroundColor:
                                const Color.fromARGB(255, 89, 189, 179),
                          ),
                          onPressed: _isLoading ? null : _handleSignup,
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  "Register",
                                  style: TextStyle(
                                    fontSize: context.responsiveFont(12),
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(8)),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Back to role selection"),
                      ),
                      SizedBox(height: context.responsiveValue(15)),
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
