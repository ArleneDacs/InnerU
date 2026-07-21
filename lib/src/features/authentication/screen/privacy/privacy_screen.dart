import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

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

  @override
  void dispose() {
    verificationController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor:
                companyTheme.isDark ? companyTheme.surfaceColor : null,
            foregroundColor: companyTheme.isDark ? companyTheme.inkColor : null,
            surfaceTintColor: Colors.transparent,
            title: Text(widget.title),
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildButtons(context, "Delete Account", companyTheme),
                  SizedBox(height: 12),
                  Text(
                    "This permanently deletes your InnerU account and profile data.",
                    style: TextStyle(color: companyTheme.mutedInkColor),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButtons(
    BuildContext context,
    String label,
    CompanyThemeData companyTheme,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: companyTheme.isDark
            ? companyTheme.surfaceColor
            : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD95555).withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            openDelete();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD95555).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete_forever_outlined,
                    color: const Color(0xFFD95555),
                    size: 22,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFD95555),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 15,
                  color: const Color(0xFFD95555),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future openDelete() => showDialog(
        context: context,
        barrierDismissible: !_isDeleting,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFD95555),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete account?',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your InnerU account and profile data. You will be signed out when deletion is complete.',
                  style: TextStyle(fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 16),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'To verify, type ',
                        style: TextStyle(fontSize: 14),
                      ),
                      TextSpan(
                        text: 'delete account',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      TextSpan(
                        text: ' below:',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: verificationController,
                  decoration: const InputDecoration(
                    hintText: 'delete account',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isDeleting
                  ? null
                  : () {
                      verificationController.clear();
                      passwordController.clear();
                      Navigator.of(context).pop();
                    },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD95555),
                foregroundColor: Colors.white,
              ),
              onPressed: _isDeleting ? null : deleteAccount,
              child: Text(_isDeleting ? 'Deleting...' : 'Delete account'),
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

    final session = AuthService.instance.currentSession;
    if (session == null) {
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
        password: passwordText.isEmpty ? null : passwordText,
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
