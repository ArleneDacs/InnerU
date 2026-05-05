import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/auth/auth_role_home.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/signup.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String _selectedRole = 'user';
  bool _isLoading = false;
  bool _acceptedTerms = false;

  Future<void> _handleGoogleSignup() async {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please accept the Terms and Conditions."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final error = await AuthService().signUpWithGoogle(
      role: _selectedRole,
      termsAccepted: _acceptedTerms,
    );

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
        MaterialPageRoute(
          builder: (context) => AuthRoleHome(preferredRole: _selectedRole),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentSpacing = context.responsiveValue(28);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF8FBF8),
                    Color(0xFFE9F2EC),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: 20,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: ResponsiveContent(
                padding: EdgeInsets.symmetric(
                  horizontal: context.responsiveWidth(regular: 24, tablet: 32),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: context.screenHeight - 60,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.back),
                      ),
                      SizedBox(height: context.responsiveValue(12)),
                      Text(
                        "Choose your role",
                        style: TextStyle(
                          fontSize: context.responsiveFont(28),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      Text(
                        "Slide between User and Coach, then continue with email or Google.",
                        style: TextStyle(
                          fontSize: context.responsiveFont(15),
                          color: Colors.black54,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      Container(
                        height: context.responsiveValue(72, min: 0.9, max: 1.1),
                        padding: EdgeInsets.all(context.responsiveValue(6)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final segmentWidth =
                                (constraints.maxWidth - 12) / 2;

                            return Stack(
                              children: [
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                  left: _selectedRole == 'user'
                                      ? 0
                                      : segmentWidth,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: segmentWidth,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(34),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF59BDB3),
                                          Color(0xFF8ED1B8),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSliderOption(
                                        title: 'User',
                                        icon: CupertinoIcons.person_fill,
                                        role: 'user',
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildSliderOption(
                                        title: 'Coach',
                                        icon: CupertinoIcons.person_2_fill,
                                        role: 'coach',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: double.infinity,
                        padding: EdgeInsets.all(context.responsiveValue(22)),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedRole == 'coach'
                                  ? "Coach account"
                                  : "User account",
                              style: TextStyle(
                                fontSize: context.responsiveFont(22),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: context.responsiveValue(10)),
                            Text(
                              _selectedRole == 'coach'
                                  ? "Use this if you're joining as a coach and want coach access saved on your account."
                                  : "Use this if you're creating a normal self-care user account.",
                              style: TextStyle(
                                fontSize: context.responsiveFont(14),
                                color: Colors.black54,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      _buildTermsAgreement(context),
                      SizedBox(height: context.responsiveValue(16)),
                      SizedBox(
                        width: double.infinity,
                        height:
                            context.responsiveValue(52, min: 0.95, max: 1.05),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF59BDB3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SignupScreen(
                                        selectedRole: _selectedRole,
                                      ),
                                    ),
                                  );
                                },
                          child: const Text(
                            "Continue with email",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: contentSpacing),
                      SizedBox(
                        width: double.infinity,
                        height:
                            context.responsiveValue(52, min: 0.95, max: 1.05),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleGoogleSignup,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      "assets/logo/Google.png",
                                      width: context.responsiveValue(28),
                                    ),
                                    SizedBox(
                                        width: context.responsiveValue(10)),
                                    const Text(
                                      "Continue with Google",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
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

  Widget _buildSliderOption({
    required String title,
    required IconData icon,
    required String role,
  }) {
    final isSelected = _selectedRole == role;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRole = role;
        });
      },
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.black54,
              size: context.responsiveValue(18),
            ),
            SizedBox(width: context.responsiveValue(8)),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: context.responsiveFont(15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsAgreement(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.responsiveValue(12)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE5D4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _acceptedTerms,
            activeColor: const Color(0xFF59BDB3),
            onChanged: _isLoading
                ? null
                : (value) {
                    setState(() {
                      _acceptedTerms = value ?? false;
                    });
                  },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: _showTermsAndConditions,
                child: const Text.rich(
                  TextSpan(
                    text: "I agree to InnerU's ",
                    children: [
                      TextSpan(
                        text: "Terms and Conditions",
                        style: TextStyle(
                          color: Color(0xFF3E9189),
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(text: "."),
                    ],
                  ),
                  style: TextStyle(height: 1.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTermsAndConditions() {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("InnerU Terms and Conditions"),
        content: const SingleChildScrollView(
          child: Text(
            "Last updated: May 5, 2026\n\n"
            "By creating an InnerU account, you agree to use the app as a self-care companion for personal wellness tracking, reflection, community support, and coach communication.\n\n"
            "InnerU is not a medical, mental health, nutrition, or emergency service. Information from fasting, calories, sleep, steps, meditation, mood tracking, journaling, coaches, or community posts is for general self-care only and should not replace advice from qualified professionals. If you feel unsafe, unwell, or in crisis, contact local emergency services or a trusted professional immediately.\n\n"
            "You are responsible for the accuracy of the information you enter, including food intake, fasting times, sleep sessions, mood check-ins, notes, and profile details. You should choose goals that are safe for your health and personal circumstances.\n\n"
            "Be respectful in community posts, comments, coach chats, and shared notes. Do not harass others, post harmful advice, share illegal content, impersonate someone, or upload content that violates another person's privacy or rights.\n\n"
            "Coaches may provide support and accountability, but coach conversations in InnerU do not create a medical provider relationship unless separately agreed outside the app. Do not use coach chat for emergencies.\n\n"
            "InnerU may store account details, wellness records, mood entries, notes, chat data, points, and app preferences to provide the service. You agree that this data may be used to show your progress, personalize your experience, support community features, and maintain your account.\n\n"
            "You must keep your login details secure. You are responsible for activity under your account. If you believe your account has been accessed without permission, change your password or contact support.\n\n"
            "InnerU may change, suspend, or remove features when needed to improve safety, reliability, or the user experience. Continued use of the app means you accept the latest terms.\n\n"
            "If you do not agree with these terms, do not create an account or use InnerU.",
            style: TextStyle(height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _acceptedTerms = true;
              });
            },
            child: const Text("I Agree"),
          ),
        ],
      ),
    );
  }
}
