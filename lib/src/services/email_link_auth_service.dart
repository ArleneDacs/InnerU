import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/forget_password/reset_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailLinkAuthService {
  EmailLinkAuthService._();

  static final EmailLinkAuthService instance = EmailLinkAuthService._();

  static const String continueUrl =
      'https://selfcare-1476e.firebaseapp.com/email-link-login';
  static const String passwordResetContinueUrl =
      'https://selfcare-1476e.firebaseapp.com/password-reset';
  static const String _pendingEmailKey = 'pending_email_link_email';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _lastHandledResetCode;
  bool _initialized = false;

  Future<void> savePendingEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingEmailKey, email);
  }

  Future<void> clearPendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingEmailKey);
  }

  Future<String?> getPendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingEmailKey);
  }

  Future<void> init({GlobalKey<NavigatorState>? navigatorKey}) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    if (kIsWeb) {
      await tryHandleLink(Uri.base.toString());
      return;
    }

    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        await tryHandleLink(initialLink.toString());
      }
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      unawaited(tryHandleLink(uri.toString()));
    });
  }

  Future<bool> tryHandleLink(String link) async {
    return tryHandlePasswordResetLink(link);
  }

  Future<bool> tryHandlePasswordResetLink(String link) async {
    final actionUri = _extractPasswordResetUri(link);
    if (actionUri == null) return false;

    final mode = actionUri.queryParameters['mode'];
    if (mode != 'resetPassword') {
      return false;
    }
    final token = actionUri.queryParameters['token'] ??
        actionUri.queryParameters['oobCode'];
    final email = actionUri.queryParameters['email'];
    if (token == null || token.isEmpty || email == null || email.isEmpty) {
      return false;
    }
    if (_lastHandledResetCode == token) return true;
    _lastHandledResetCode = token;

    await _openPasswordResetScreen(token, email);
    return true;
  }

  Uri? _extractFirebaseActionUri(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    if (uri.queryParameters.containsKey('mode') &&
        uri.queryParameters.containsKey('oobCode')) {
      return uri;
    }

    for (final key in const ['link', 'deep_link_id']) {
      final nestedLink = uri.queryParameters[key];
      if (nestedLink == null || nestedLink.isEmpty) continue;

      final nestedUri = Uri.tryParse(nestedLink);
      if (nestedUri != null &&
          nestedUri.queryParameters.containsKey('mode') &&
          nestedUri.queryParameters.containsKey('oobCode')) {
        return nestedUri;
      }
    }

    return null;
  }

  Uri? _extractPasswordResetUri(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;

    if (uri.queryParameters['mode'] == 'resetPassword' &&
        (uri.queryParameters.containsKey('token') ||
            uri.queryParameters.containsKey('oobCode'))) {
      return uri;
    }

    final actionUri = _extractFirebaseActionUri(link);
    if (actionUri != null &&
        actionUri.queryParameters['mode'] == 'resetPassword') {
      return actionUri;
    }

    return null;
  }

  Future<void> _openPasswordResetScreen(String token, String email) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final navigator = _navigatorKey?.currentState;
      if (navigator != null && navigator.mounted) {
        await navigator.push(
          MaterialPageRoute(
            builder: (context) => ResetPasswordScreen(
              token: token,
              email: email,
            ),
          ),
        );
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
    _navigatorKey = null;
    _lastHandledResetCode = null;
    _initialized = false;
  }
}
