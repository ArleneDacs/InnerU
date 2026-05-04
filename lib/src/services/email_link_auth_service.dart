import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailLinkAuthService {
  EmailLinkAuthService._();

  static final EmailLinkAuthService instance = EmailLinkAuthService._();

  static const String continueUrl =
      'https://selfcare-1476e.firebaseapp.com/email-link-login';
  static const String _pendingEmailKey = 'pending_email_link_email';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
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

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      await tryHandleEmailLink(Uri.base.toString());
      return;
    }

    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        await tryHandleEmailLink(initialLink.toString());
      }
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      unawaited(tryHandleEmailLink(uri.toString()));
    });
  }

  Future<bool> tryHandleEmailLink(String link) async {
    if (!FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      return false;
    }

    final email = await getPendingEmail();
    if (email == null || email.isEmpty) {
      return false;
    }

    await FirebaseAuth.instance.signInWithEmailLink(
      email: email,
      emailLink: link,
    );
    await clearPendingEmail();
    return true;
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }
}
