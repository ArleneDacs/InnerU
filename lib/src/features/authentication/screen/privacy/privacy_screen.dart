import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.title});
  final String title;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreen();
}

class _PrivacyScreen extends State<PrivacyScreen> {
  TextEditingController verificationController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool _isDeleting = false;

  bool get _usesPasswordProvider {
    final user = FirebaseAuth.instance.currentUser;
    return user?.providerData
            .any((provider) => provider.providerId == 'password') ??
        false;
  }

  @override
  void dispose() {
    verificationController.dispose();
    passwordController.dispose();
    super.dispose();
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
              _buildButtons(context, "Delete Account"),
              SizedBox(height: 12),
              Text(
                "This permanently deletes your InnerU account and profile data.",
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtons(BuildContext context, String label) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: TextButton(
        onPressed: () {
          openDelete();
        },
        style: ButtonStyle(
          padding: WidgetStateProperty.all(
              EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
          overlayColor: WidgetStateProperty.all(Colors.grey.shade200),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 17, color: Colors.black)),
            SizedBox(width: 10),
            Image.asset(
              "assets/images/reminder.png",
              height: 25,
              width: 25,
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Future openDelete() => showDialog(
        context: context,
        barrierDismissible: !_isDeleting,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            'Are you sure you want to delete your account?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    '⚠️ This is extremely important!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 30),
                Text(
                  'This permanently deletes your InnerU account and profile data. You will be signed out when deletion is complete.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'To verify, type ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      TextSpan(
                        text: 'delete account',
                        style: TextStyle(
                          color: Colors.white,
                          fontStyle: FontStyle.italic,
                          fontSize: 14,
                        ),
                      ),
                      TextSpan(
                        text: ' below:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: verificationController,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    decoration: InputDecoration(
                      labelStyle: TextStyle(color: Colors.white70),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white, width: 2.0),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                if (_usesPasswordProvider) ...[
                  Text(
                    'Confirm Password:',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      decoration: InputDecoration(
                        labelStyle: TextStyle(color: Colors.white70),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white, width: 2.0),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'You will be asked to confirm with your sign-in provider before deletion.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _isDeleting
                      ? null
                      : () {
                          verificationController.clear();
                          passwordController.clear();
                          Navigator.of(context).pop();
                        },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: _isDeleting ? null : deleteAccount,
                  child: Text(
                    _isDeleting ? 'Deleting...' : 'Delete this account',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  void deleteAccount() async {
    final verificationText = verificationController.text.trim().toLowerCase();
    final passwordText = passwordController.text.trim();

    if (verificationText != "delete account") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please type 'delete account' to verify."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_usesPasswordProvider && passwordText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Password cannot be empty."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("No user signed in."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isDeleting = true;
      });

      await AuthService().deleteCurrentUserAccount(
        password: _usesPasswordProvider ? passwordText : null,
      );

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Account deleted successfully."),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      print('Error during account deletion: $e');
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to delete account: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
