import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple_sign_in;
import 'package:selfcare_projects/src/features/authentication/screen/auth/auth_role_home.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgetpassword_otp/forgotpasswordotp.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/forgotpassword_mail/forgotpasswordmail.dart';
import 'package:selfcare_projects/src/features/authentication/screen/signup/role_selection_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _missingAccountMessage = AuthService.missingAccountMessage;
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _loginError;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool get _supportsAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _showLoginError(String message) {
    if (message == _missingAccountMessage) {
      setState(() {
        _loginError = null;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() {
      _loginError = message;
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    final error = await AuthService.instance.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (error == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthRoleHome()),
      );
    } else {
      _showLoginError(error);
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showForgotPasswordOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Reset Password",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Choose how you want to reset your password.",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _buildResetOption(
                icon: CupertinoIcons.envelope_fill,
                title: "Reset via Email",
                subtitle: "We'll send a reset link to your inbox",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ForgotPasswordMail()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildResetOption(
                icon: CupertinoIcons.phone_fill,
                title: "Reset via Phone",
                subtitle: "We'll send a one-time code by SMS",
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

  Widget _buildResetOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryDark, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
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
      _showLoginError(error);
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _handleAppleLogin() async {
    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    final error = await AuthService().signInWithApple();

    if (!mounted) return;

    if (error == AuthService.userCancelledAppleFlow) {
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
    }

    _showLoginError(error);

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final verticalTopSpace = context.screenHeight * 0.1;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: context.isTabletWidth ? 680 : double.infinity,
                ),
                child: Image.asset(
                  "assets/images/login-image/login.png",
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          margin: EdgeInsets.only(
                            bottom: context.responsiveValue(20),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.dangerSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.exclamationmark_circle_fill,
                                color: AppColors.danger,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _loginError!,
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _loginError = null;
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    CupertinoIcons.xmark,
                                    color: AppColors.danger,
                                    size: 16,
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      Text(
                        "InnerU",
                        style: TextStyle(
                          fontSize: context.responsiveFont(38),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Parisienne',
                          color: AppColors.primaryDeep,
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(6)),
                      Text(
                        "Welcome back — sign in to continue",
                        style: TextStyle(
                          fontSize: context.responsiveFont(14),
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(30)),
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
                        height:
                            context.responsiveValue(50, min: 0.95, max: 1.05),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleLogin,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  "Log in",
                                  style: TextStyle(
                                    fontSize: context.responsiveFont(15),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(20)),
                      const Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: AppColors.border,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              "OR",
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: AppColors.border,
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
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white,
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppColors.softShadow,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              Image.asset(
                                "assets/logo/Google.png",
                                width: context.responsiveValue(26),
                              ),
                              Text(
                                "Sign in with Google",
                                style: TextStyle(
                                  fontSize: context.responsiveFont(15),
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_supportsAppleSignIn) ...[
                        SizedBox(height: context.responsiveValue(16)),
                        SizedBox(
                          width: double.infinity,
                          height:
                              context.responsiveValue(50, min: 0.95, max: 1.05),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: _isLoading,
                                  child: Opacity(
                                    opacity: _isLoading ? 0.72 : 1,
                                    child: apple_sign_in.SignInWithAppleButton(
                                      onPressed: _handleAppleLogin,
                                      height: context.responsiveValue(
                                        50,
                                        min: 0.95,
                                        max: 1.05,
                                      ),
                                      text: "Sign in with Apple",
                                      borderRadius: BorderRadius.circular(8),
                                      iconAlignment:
                                          apple_sign_in.IconAlignment.left,
                                    ),
                                  ),
                                ),
                              ),
                              if (_isLoading)
                                const Positioned.fill(
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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
