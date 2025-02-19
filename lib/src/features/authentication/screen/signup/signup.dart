import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart'; // For Google Sign-In
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Authentication
/*import 'package:sign_in_with_apple/sign_in_with_apple.dart'; // For Apple Sign-In*/

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _retypepassController = TextEditingController();

  // Email Validation
  bool _isValidEmail(String email) {
    final RegExp emailRegex = RegExp(
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
    return emailRegex.hasMatch(email);
  }

  // Phone Number Validation
  bool _isValidPhoneNumber(String number) {
    final RegExp phoneRegex = RegExp(r'^[0-9]{10,15}$');
    return phoneRegex.hasMatch(number);
  }

  // Password Validation
  bool _isValidPassword(String password) {
    final RegExp passwordRegex = RegExp(
        r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$');
    return passwordRegex.hasMatch(password);
  }

  // Function to handle Email Signup
  void _handleSignup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    String? error = await AuthService().signUpUser(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      number: _numberController.text.trim(),
      retypepassword: _retypepassController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (error == null) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Verify Your Email"),
            content: const Text(
                "A verification email has been sent. Please check your email and verify your account."),
            actions: [
              TextButton(
                onPressed: () {
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

  // Function to handle Google Sign-In
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Ensure the account picker appears by signing out first
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return; // User canceled the sign-in process
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      if (!userCredential.user!.emailVerified) {
        await userCredential.user!.sendEmailVerification();
      }

      Navigator.pushReplacementNamed(context, '/home');
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  // Function to handle Apple Sign-In
  /*Future<void> _handleAppleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oAuthProvider = OAuthProvider("apple.com");
      final credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in with Firebase using Apple credentials
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Navigate to dashboard after Apple sign-in
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Apple sign-in failed: $error'),
            backgroundColor: Colors.red),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }*/

  @override
  Widget build(BuildContext context) {
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
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 130),
                    const Text(
                      "Create an Account",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Parisienne',
                      ),
                    ),
                    const SizedBox(height: 13),
                    // Username Field
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: "Username"),
                      validator: (value) =>
                          value!.isEmpty ? "Username cannot be empty" : null,
                    ),
                    const SizedBox(height: 10),
                    // Email Field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: "Email"),
                      validator: (value) {
                        if (value!.isEmpty) return "Email cannot be empty";
                        if (!_isValidEmail(value))
                          return "Invalid email format!";
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // Phone Number Field
                    TextFormField(
                      controller: _numberController,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: "Phone Number"),
                      validator: (value) {
                        if (value!.isEmpty)
                          return "Phone number cannot be empty";
                        if (!_isValidPhoneNumber(value))
                          return "Invalid phone number!";
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: "Password",
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible
                              ? CupertinoIcons.eye_slash
                              : CupertinoIcons.eye),
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
                          return "Weak password! It must contain:\n"
                              "- At least one lowercase letter\n"
                              "- At least one uppercase letter\n"
                              "- At least one special character (!@#%^&*()-+)\n"
                              "- At least one digit\n"
                              "- Minimum length of 8 characters";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // Re-type Password Field
                    TextFormField(
                      controller: _retypepassController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        labelText: "Re-type Password",
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible
                              ? CupertinoIcons.eye_slash
                              : CupertinoIcons.eye),
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
                    const SizedBox(height: 25),
                    // Register Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
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
                                color: Colors.white)
                            : Text(
                                "Register",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Already have an account? Login"),
                    ),
                    const SizedBox(height: 10),
                    // Divider with OR
                    Row(
                      children: [
                        Expanded(
                            child: Divider(
                                color: const Color.fromARGB(255, 91, 195, 183),
                                thickness: 1)),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text("OR"),
                        ),
                        Expanded(
                            child: Divider(
                                color: const Color.fromARGB(255, 91, 195, 183),
                                thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Google Sign-In Button
                    // Google & Apple Sign-In Buttons in the same row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _isLoading ? null : _handleGoogleSignIn,
                          child: Row(
                            children: [
                              Image.asset("assets/logo/google.png", width: 50),
                              const SizedBox(width: 10),
                              const Text("Google",
                                  style: TextStyle(fontSize: 16)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20), // Space between buttons
                        GestureDetector(
                          /* onTap: _isLoading ? null : _handleAppleSignIn, */
                          child: Row(
                            children: [
                              Image.asset("assets/logo/ios.png", width: 30),
                              const SizedBox(width: 10),
                              const Text("Apple",
                                  style: TextStyle(fontSize: 16)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
