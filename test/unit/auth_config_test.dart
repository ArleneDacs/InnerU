import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/email_link_auth_service.dart';

void main() {
  group('Email verification configuration', () {
    test('continue URL points at the Firebase auth domain', () {
      final uri = Uri.parse(EmailLinkAuthService.continueUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'selfcare-1476e.firebaseapp.com');
      expect(uri.path, '/email-link-login');
    });

    test('verification email settings target both mobile apps', () {
      final settings = AuthService.emailVerificationSettings;

      expect(settings.url, EmailLinkAuthService.continueUrl);
      expect(settings.handleCodeInApp, isFalse);
      expect(settings.androidPackageName, 'com.valenin.inneru');
      expect(settings.iOSBundleId, 'com.valenin.inneru');
      expect(settings.androidInstallApp, isFalse);
      expect(settings.androidMinimumVersion, '21');
    });

    test('password reset settings target Android app links', () {
      final settings = AuthService.passwordResetSettings;

      expect(settings.url, EmailLinkAuthService.passwordResetContinueUrl);
      expect(settings.handleCodeInApp, isTrue);
      expect(settings.androidPackageName, 'com.valenin.inneru');
      expect(settings.iOSBundleId, 'com.valenin.inneru');
      expect(settings.androidInstallApp, isFalse);
      expect(settings.androidMinimumVersion, '21');
    });
  });

  group('AuthService sentinel values', () {
    test('cancellation sentinels are distinct from real error messages', () {
      expect(AuthService.userCancelledGoogleFlow, '__google_cancelled__');
      expect(AuthService.userCancelledAppleFlow, '__apple_cancelled__');
      expect(
        AuthService.userCancelledGoogleFlow,
        isNot(AuthService.userCancelledAppleFlow),
      );
    });
  });
}
