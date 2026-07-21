import 'package:flutter/foundation.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';

class AuthService {
  AuthService._();

  factory AuthService() => instance;

  static final AuthService instance = AuthService._();

  static const String userCancelledGoogleFlow = "__google_cancelled__";
  static const String userCancelledAppleFlow = "__apple_cancelled__";
  static const String missingAccountMessage =
      "User not found. Please create an account first.";

  final AppSessionService _sessionService = AppSessionService.instance;
  final ApiClient _apiClient = ApiClient.instance;

  Stream<AppSession?> get sessionStream => _sessionService.stream;
  AppSession? get currentSession => _sessionService.current;
  String? get currentUserId => _sessionService.currentUserId;

  static Future<void> sendVerificationEmail([Object? user]) async {
    // Laravel auth does not use Firebase-style verification links in this app.
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
        await _sessionService.clear();
      }
    } catch (_) {
      await _sessionService.clear();
    }
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
      await _storeSessionFromAuthResponse(response);
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
    return "Google sign-in is not connected to Laravel yet. Please use email and password.";
  }

  Future<String?> signUpWithGoogle({
    required String role,
    required String companyCode,
    required bool continueWithoutCompany,
    required bool termsAccepted,
  }) async {
    return "Google sign-up is not connected to Laravel yet. Please use email and password.";
  }

  Future<String?> signInWithApple() async {
    return "Apple sign-in is not connected to Laravel yet. Please use email and password.";
  }

  Future<String?> signUpWithApple({
    required String role,
    required String companyCode,
    required bool continueWithoutCompany,
    required bool termsAccepted,
  }) async {
    return "Apple sign-up is not connected to Laravel yet. Please use email and password.";
  }

  Future<void> signOutGoogle() async {
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
    );
    await _sessionService.setSession(session);
  }
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
