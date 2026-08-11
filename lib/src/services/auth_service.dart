import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple_sign_in;
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/email_link_auth_service.dart';

class ActionCodeSettings {
  const ActionCodeSettings({
    required this.url,
    required this.handleCodeInApp,
    required this.androidPackageName,
    required this.iOSBundleId,
    required this.androidInstallApp,
    required this.androidMinimumVersion,
  });

  final String url;
  final bool handleCodeInApp;
  final String androidPackageName;
  final String iOSBundleId;
  final bool androidInstallApp;
  final String androidMinimumVersion;
}

class AuthService {
  AuthService._() {
    _apiClient.setUnauthorizedHandler(_invalidateCurrentSession);
  }

  factory AuthService() => instance;

  static final AuthService instance = AuthService._();

  static const String userCancelledGoogleFlow = "__google_cancelled__";
  static const String userCancelledAppleFlow = "__apple_cancelled__";
  static const String missingAccountMessage =
      "User not found. Please create an account first.";
  static const String emailNotVerifiedMessage =
      "Please verify your email first.";
  static const String _googleServerClientId =
      '609604667702-2898tlqiuhgt69viubl09cq4ninu78g9.apps.googleusercontent.com';

  static const ActionCodeSettings emailVerificationSettings =
      ActionCodeSettings(
    url: EmailLinkAuthService.continueUrl,
    handleCodeInApp: false,
    androidPackageName: 'com.valenin.inneru',
    iOSBundleId: 'com.valenin.inneru',
    androidInstallApp: false,
    androidMinimumVersion: '21',
  );

  static const ActionCodeSettings passwordResetSettings = ActionCodeSettings(
    url: EmailLinkAuthService.passwordResetContinueUrl,
    handleCodeInApp: true,
    androidPackageName: 'com.valenin.inneru',
    iOSBundleId: 'com.valenin.inneru',
    androidInstallApp: false,
    androidMinimumVersion: '21',
  );

  final AppSessionService _sessionService = AppSessionService.instance;
  final ApiClient _apiClient = ApiClient.instance;
  String? _pendingVerificationEmail;
  bool _lastVerificationEmailSent = true;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: _googleServerClientId,
  );

  Stream<AppSession?> get sessionStream => _sessionService.stream;
  AppSession? get currentSession => _sessionService.current;
  String? get currentUserId => _sessionService.currentUserId;
  String? get pendingVerificationEmail => _pendingVerificationEmail;

  /// Persists a non-authentication profile preference alongside the existing
  /// secure session payload so a restored session can use it before any
  /// background profile refresh completes.
  Future<void> updateDefaultLandingScreen(String defaultLandingScreen) async {
    final session = _sessionService.current;
    if (session == null) return;
    await _sessionService.setSession(
      session.copyWith(defaultLandingScreen: defaultLandingScreen),
    );
  }

  /// Whether the server actually delivered the verification email for the
  /// most recent signup, as opposed to just creating the pending account.
  /// SMTP failures are silent otherwise: the server still reports success
  /// so the account gets created, and the user is left waiting on an email
  /// that never sent.
  bool get lastVerificationEmailSent => _lastVerificationEmailSent;

  void clearPendingVerificationEmail() {
    _pendingVerificationEmail = null;
  }

  static Future<String?> sendVerificationEmail({
    required String email,
  }) async {
    try {
      final response = await ApiClient.instance.postJson(
        '/api/auth/email/verification-notification',
        {'email': email.trim()},
      );
      if (response['verification_email_sent'] == false) {
        return response['message']?.toString() ??
            'We could not send the verification email right now. Please try again later.';
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Verification email send failed: $e');
      return 'Unable to send verification email. Please try again.';
    }
  }

  Future<void> initialize() async {
    await _sessionService.initialize();
    final session = _sessionService.current;
    if (session == null) {
      return;
    }

    try {
      final response = await _apiClient.getJson(
        '/api/me',
        token: session.token,
      );
      await _syncSessionFromResponse(
        response,
        token: session.token,
        fallbackSession: session,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _sessionService.clearIfCurrentTokenMatches(session.token);
      }
    } catch (e) {
      // Network/connectivity failure (e.g. no internet at launch) -- keep
      // the cached session so the user stays logged in offline. Only a
      // confirmed 401 from the server means the token is actually invalid.
      debugPrint('Failed to refresh session on launch: $e');
    }
  }

  void _invalidateCurrentSession(String failedToken) {
    // ApiClient calls this only for a 401 response to an authenticated
    // request. It is intentionally fire-and-forget so every service gets a
    // consistent invalid-session redirect without delaying its own error
    // handling path.
    unawaited(_sessionService.clearIfCurrentTokenMatches(failedToken));
  }

  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.postJson(
        '/api/auth/login',
        {
          'email': email.trim(),
          'password': password,
        },
      );
      await _storeSessionFromAuthResponse(response);
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        return "Login failed. Wrong Email or Password";
      }
      if (e.statusCode == 403) {
        return emailNotVerifiedMessage;
      }
      return e.message;
    } catch (e) {
      debugPrint('Login failed: $e');
      return "Login failed. Please try again.";
    }
  }

  Future<String?> signUpUser({
    required String username,
    required String email,
    required String password,
    required String number,
    required String retypepassword,
    required String role,
    required String companyCode,
    required bool continueWithoutCompany,
    required bool termsAccepted,
  }) async {
    try {
      if (!termsAccepted) {
        return "You must accept the Terms and Conditions to create an account.";
      }
      if (password != retypepassword) {
        return "Passwords do not match.";
      }

      final companyCodeValue =
          continueWithoutCompany ? null : companyCode.trim().toUpperCase();
      final response = await _apiClient.postJson(
        '/api/auth/register',
        {
          'name': username.trim(),
          'email': email.trim(),
          'password': password,
          'number': number.trim().isEmpty ? null : number.trim(),
          'role': role.trim().isEmpty ? 'user' : role.trim(),
          'company_code': companyCodeValue,
          'company_name': companyCodeValue,
        },
      );
      _lastVerificationEmailSent = response['verification_email_sent'] != false;
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 422 && e.errors != null) {
        final firstError = e.errors!.values
            .expand((value) => value is List ? value : [value])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .cast<String?>()
            .firstOrNull;
        return firstError ?? e.message;
      }
      return e.message;
    } catch (e) {
      debugPrint('Signup failed: $e');
      return "Signup failed. Please try again.";
    }
  }

  Future<String?> signInWithGoogle() async {
    return _authenticateWithGoogle(createAccount: false);
  }

  Future<String?> signUpWithGoogle({
    required String role,
    required String companyCode,
    required bool continueWithoutCompany,
    required bool termsAccepted,
  }) async {
    if (!termsAccepted) {
      return "You must accept the Terms and Conditions to continue.";
    }

    return _authenticateWithGoogle(
      createAccount: true,
      role: role,
      companyCode: companyCode,
      continueWithoutCompany: continueWithoutCompany,
    );
  }

  Future<String?> signInWithApple() async {
    return _authenticateWithApple(createAccount: false);
  }

  Future<String?> signUpWithApple({
    required String role,
    required String companyCode,
    required bool continueWithoutCompany,
    required bool termsAccepted,
  }) async {
    if (!termsAccepted) {
      return "You must accept the Terms and Conditions to continue.";
    }

    return _authenticateWithApple(
      createAccount: true,
      role: role,
      companyCode: companyCode,
      continueWithoutCompany: continueWithoutCompany,
    );
  }

  Future<void> signOutGoogle() async {
    await _googleSignIn.signOut();
    _pendingVerificationEmail = null;
    await _sessionService.clear();
  }

  Future<void> deleteCurrentUserAccount({String? password}) async {
    final session = _sessionService.current;
    if (session == null) {
      throw ApiException(401, 'No user signed in.');
    }

    await _apiClient.deleteJson(
      '/api/me',
      token: session.token,
    );
    await _sessionService.clear();
  }

  Future<void> updateEmailVerificationStatus() async {
    // Email verification is handled server-side in the future.
  }

  Future<void> _storeSessionFromAuthResponse(
    Map<String, dynamic> response,
  ) async {
    final userJson = response['user'];
    if (userJson is! Map<String, dynamic>) {
      throw ApiException(500, 'Authentication response was invalid.');
    }

    final token = response['token']?.toString();
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Authentication token was missing.');
    }

    final session = AppSession(
      id: (userJson['id'] as num).toInt(),
      token: token,
      name: userJson['name']?.toString() ?? 'User',
      email: userJson['email']?.toString() ?? '',
      role: userJson['role']?.toString() ?? 'user',
      isCoach: userJson['is_coach'] == true,
      number: userJson['number']?.toString(),
      companyCode: userJson['company_code']?.toString(),
      companyName: userJson['company_name']?.toString(),
      birthdate: userJson['birthdate']?.toString(),
      profilePic: userJson['profile_pic']?.toString(),
      defaultLandingScreen: userJson['defaultScreen']?.toString() ??
          userJson['default_landing_screen']?.toString() ??
          'dashboard',
    );
    await _sessionService.setSession(session);
  }

  Future<void> _syncSessionFromResponse(
    Map<String, dynamic> response, {
    required String token,
    required AppSession fallbackSession,
  }) async {
    final userJson = response['user'];
    if (userJson is! Map<String, dynamic>) {
      await _sessionService.setSession(fallbackSession);
      return;
    }

    final session = AppSession(
      id: (userJson['id'] as num?)?.toInt() ?? fallbackSession.id,
      token: token,
      name: userJson['name']?.toString() ?? fallbackSession.name,
      email: userJson['email']?.toString() ?? fallbackSession.email,
      role: userJson['role']?.toString() ?? fallbackSession.role,
      isCoach: userJson['is_coach'] == true || fallbackSession.isCoach,
      number: userJson['number']?.toString() ?? fallbackSession.number,
      companyCode:
          userJson['company_code']?.toString() ?? fallbackSession.companyCode,
      companyName:
          userJson['company_name']?.toString() ?? fallbackSession.companyName,
      birthdate: userJson['birthdate']?.toString() ?? fallbackSession.birthdate,
      profilePic:
          userJson['profile_pic']?.toString() ?? fallbackSession.profilePic,
      defaultLandingScreen: userJson['defaultScreen']?.toString() ??
          userJson['default_landing_screen']?.toString() ??
          fallbackSession.defaultLandingScreen,
    );
    await _sessionService.setSession(session);
  }

  Future<String?> _authenticateWithGoogle({
    required bool createAccount,
    String? role,
    String? companyCode,
    bool continueWithoutCompany = false,
  }) async {
    try {
      _pendingVerificationEmail = null;
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return userCancelledGoogleFlow;
      }

      final auth = await googleUser.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        await _googleSignIn.signOut();
        return "Google sign-in could not retrieve a secure token. Please try again.";
      }

      final response = await _apiClient.postJson(
        '/api/auth/google',
        {
          'id_token': idToken,
          'create_account': createAccount,
          if (role != null) 'role': role,
          if (companyCode != null) 'company_code': companyCode,
          if (companyCode != null) 'company_name': companyCode,
          if (continueWithoutCompany) 'continue_without_company': true,
        },
      );

      final verificationRequired = response['verification_required'] == true;
      if (verificationRequired) {
        _pendingVerificationEmail =
            response['email']?.toString() ?? googleUser.email;
        _lastVerificationEmailSent =
            response['verification_email_sent'] != false;
        return null;
      }

      await _storeSessionFromAuthResponse(response);
      _pendingVerificationEmail = null;
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 401 && e.message.isNotEmpty) {
        return e.message;
      }
      return e.message;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      return "Google sign-in failed. Please try again.";
    }
  }

  Future<String?> _authenticateWithApple({
    required bool createAccount,
    String? role,
    String? companyCode,
    bool continueWithoutCompany = false,
  }) async {
    try {
      _pendingVerificationEmail = null;

      final rawNonce = apple_sign_in.generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential =
          await apple_sign_in.SignInWithApple.getAppleIDCredential(
        scopes: const [
          apple_sign_in.AppleIDAuthorizationScopes.email,
          apple_sign_in.AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        return "Apple sign-in could not retrieve a secure token. Please try again.";
      }

      final fullName = _appleDisplayName(
        givenName: credential.givenName,
        familyName: credential.familyName,
        email: credential.email,
      );

      final response = await _apiClient.postJson(
        '/api/auth/apple',
        {
          'identity_token': identityToken,
          'raw_nonce': rawNonce,
          'create_account': createAccount,
          'apple_user_id': credential.userIdentifier,
          'email': credential.email,
          'given_name': credential.givenName,
          'family_name': credential.familyName,
          if (fullName != null) 'full_name': fullName,
          if (role != null) 'role': role,
          if (companyCode != null) 'company_code': companyCode,
          if (companyCode != null) 'company_name': companyCode,
          if (continueWithoutCompany) 'continue_without_company': true,
        },
      );

      final verificationRequired = response['verification_required'] == true;
      if (verificationRequired) {
        _pendingVerificationEmail =
            response['email']?.toString() ?? credential.email;
        _lastVerificationEmailSent =
            response['verification_email_sent'] != false;
        return null;
      }

      await _storeSessionFromAuthResponse(response);
      _pendingVerificationEmail = null;
      return null;
    } on apple_sign_in.SignInWithAppleAuthorizationException catch (e) {
      if (e.code == apple_sign_in.AuthorizationErrorCode.canceled) {
        return userCancelledAppleFlow;
      }

      return "Apple sign-in failed. Please try again.";
    } on ApiException catch (e) {
      if (e.statusCode == 401 && e.message.isNotEmpty) {
        return e.message;
      }
      return e.message;
    } catch (e) {
      debugPrint('Apple sign-in failed: $e');
      return "Apple sign-in failed. Please try again.";
    }
  }

  String? _appleDisplayName({
    String? givenName,
    String? familyName,
    String? email,
  }) {
    final parts = <String>[
      if ((givenName ?? '').trim().isNotEmpty) givenName!.trim(),
      if ((familyName ?? '').trim().isNotEmpty) familyName!.trim(),
    ];

    if (parts.isNotEmpty) {
      return parts.join(' ').trim();
    }

    final trimmedEmail = email?.trim();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) {
      return trimmedEmail.split('@').first;
    }

    return null;
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
