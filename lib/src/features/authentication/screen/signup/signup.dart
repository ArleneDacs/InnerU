import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/check_email_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    required this.selectedRole,
    this.initialCompanyCode = '',
    this.continueWithoutCompany = false,
    this.companyCodeValidator,
  });

  final String selectedRole;
  final String initialCompanyCode;
  final bool continueWithoutCompany;
  final Future<bool> Function(String companyCode)? companyCodeValidator;

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
  late final TextEditingController _companyCodeController;

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _acceptedTerms = false;
  late bool _continueWithoutCompany;
  String? _companyCodeValidationError;

  @override
  void initState() {
    super.initState();
    _companyCodeController = TextEditingController(
      text: widget.initialCompanyCode.trim().toUpperCase(),
    );
    _continueWithoutCompany = widget.continueWithoutCompany;
    if (_continueWithoutCompany) {
      _companyCodeController.clear();
    }
  }

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

  bool _isAbundance12Code(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized == 'A12' ||
        normalized.startsWith('AB12') ||
        normalized.contains('ABUND12') ||
        normalized.contains('ABUNDANCE12');
  }

  Future<void> _handleSignup() async {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please accept the Terms and Conditions."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    if (!_continueWithoutCompany) {
      final companyCode = _companyCodeController.text.trim().toUpperCase();
      try {
        final validator = widget.companyCodeValidator ??
            CompanyApiService.instance.isCompanyCodeValid;
        final isValid = await validator(companyCode);
        if (!mounted) return;
        if (!isValid) {
          setState(() {
            _companyCodeValidationError =
                CompanyApiService.invalidCompanyCodeMessage;
            _isLoading = false;
          });
          _formKey.currentState?.validate();
          return;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Unable to validate the company code. Please try again.",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final error = await AuthService().signUpUser(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      number: _numberController.text.trim(),
      retypepassword: _retypepassController.text.trim(),
      role: widget.selectedRole,
      companyCode:
          _continueWithoutCompany ? '' : _companyCodeController.text.trim(),
      continueWithoutCompany: _continueWithoutCompany,
      termsAccepted: _acceptedTerms,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (error == null) {
      _showVerificationEmailScreen();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  void _showVerificationEmailScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CheckEmailScreen(
          email: _emailController.text.trim(),
          initialSendFailed: !AuthService.instance.lastVerificationEmailSent,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _numberController.dispose();
    _retypepassController.dispose();
    _companyCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topSpacing = context.screenHeight * 0.1;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: (context.screenHeight * 0.32).clamp(170.0, 280.0),
                child: Image.asset(
                  "assets/images/login-image/signup.png",
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: topSpacing.clamp(58, 112)),
                      Text(
                        "Create an Account",
                        style: TextStyle(
                          fontSize: context.responsiveFont(28),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Parisienne',
                          color: const Color(0xFF245A55),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(4)),
                      Text(
                        "A few details, then verify your email.",
                        style: TextStyle(
                          fontSize: context.responsiveFont(14),
                          color: Colors.black54,
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
                            color:
                                const Color(0xFF59BDB3).withValues(alpha: 0.3),
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
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "Selected role: ${widget.selectedRole == 'coach' ? 'Coach' : 'User'}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF245A55),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(18)),
                      TextFormField(
                        controller: _companyCodeController,
                        enabled: !_isLoading && !_continueWithoutCompany,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: widget.selectedRole == 'coach'
                              ? "Coach Company Code"
                              : "Company Code",
                        ),
                        onChanged: (value) {
                          if (_companyCodeValidationError != null) {
                            setState(() {
                              _companyCodeValidationError = null;
                            });
                          }
                          final upperValue = value.toUpperCase();
                          if (value != upperValue) {
                            _companyCodeController.value =
                                _companyCodeController.value.copyWith(
                              text: upperValue,
                              selection: TextSelection.collapsed(
                                offset: upperValue.length,
                              ),
                            );
                          }
                        },
                        validator: (value) {
                          if (_continueWithoutCompany) return null;
                          if (value == null || value.trim().isEmpty) {
                            return "Enter a company code or tick no company";
                          }
                          if (value.trim().length < 4 &&
                              !_isAbundance12Code(value)) {
                            return CompanyApiService.invalidCompanyCodeMessage;
                          }
                          return _companyCodeValidationError;
                        },
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      _buildNoCompanyToggle(context),
                      SizedBox(height: context.responsiveValue(10)),
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
                      SizedBox(height: context.responsiveValue(18)),
                      _buildTermsAgreement(context),
                      SizedBox(height: context.responsiveValue(18)),
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
                          onPressed: _isLoading ? null : _handleSignup,
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
                                  "Register",
                                  style: TextStyle(
                                    fontSize: context.responsiveFont(15),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
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

  Widget _buildTermsAgreement(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Checkbox(
              value: _acceptedTerms,
              activeColor: const Color(0xFF59BDB3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: _isLoading
                  ? null
                  : (value) {
                      setState(() {
                        _acceptedTerms = value ?? false;
                      });
                    },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                style: TextStyle(height: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoCompanyToggle(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Checkbox(
              value: _continueWithoutCompany,
              activeColor: const Color(0xFF59BDB3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onChanged: _isLoading
                  ? null
                  : (value) {
                      setState(() {
                        _continueWithoutCompany = value ?? false;
                        _companyCodeValidationError = null;
                        if (_continueWithoutCompany) {
                          _companyCodeController.clear();
                        }
                      });
                    },
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "I don't have a company yet.",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                height: 1.2,
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
