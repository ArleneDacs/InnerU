import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/email_link_auth_service.dart';

/// Guards against iOS/Android feature drift: every capability that needs a
/// per-platform registration (deep links, permissions, URL schemes, package
/// identifiers) must be configured on BOTH platforms, so a feature that works
/// on iOS cannot silently break on Android or vice versa.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
  final entitlements =
      File('ios/Runner/Runner.entitlements').readAsStringSync();
  final watchInfoPlist =
      File('ios/InnerUWatch/Info.plist').readAsStringSync();
  final buildGradle = File('android/app/build.gradle').readAsStringSync();
  final pbxproj =
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  final checkEmailScreen = File(
    'lib/src/features/authentication/screen/login/check_email_screen.dart',
  ).readAsStringSync();

  String androidApplicationId() {
    final match =
        RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(buildGradle);
    expect(match, isNotNull, reason: 'applicationId missing from build.gradle');
    return match!.group(1)!;
  }

  List<String> iosAppLinkDomains() {
    return RegExp(r'applinks:([^<]+)<')
        .allMatches(entitlements)
        .map((m) => m.group(1)!.trim())
        .toList();
  }

  String nativeTargetBlock(String targetId, String targetName) {
    final match = RegExp(
      '$targetId /\\* $targetName \\*/ = \\{[\\s\\S]*?\\n\\t\\t\\};',
    ).firstMatch(pbxproj);
    expect(match, isNotNull, reason: '$targetName target missing from project');
    return match!.group(0)!;
  }

  group('Deep links (email link login / password reset)', () {
    test('every iOS applink domain has a matching Android intent filter', () {
      final domains = iosAppLinkDomains();
      expect(domains, isNotEmpty,
          reason: 'iOS entitlements should declare applink domains');
      for (final domain in domains) {
        expect(
          manifest.contains('android:host="$domain"'),
          isTrue,
          reason: 'iOS handles https://$domain links but AndroidManifest has '
              'no intent filter for it — the link would open a browser on '
              'Android instead of the app (forgot-password class of bug).',
        );
      }
    });

    test('email-link continue URLs use hosts both platforms can open', () {
      for (final url in [
        EmailLinkAuthService.continueUrl,
        EmailLinkAuthService.passwordResetContinueUrl,
      ]) {
        final host = Uri.parse(url).host;
        expect(manifest.contains('android:host="$host"'), isTrue,
            reason: '$url host is not app-linked on Android');
        expect(iosAppLinkDomains(), contains(host),
            reason: '$url host is not app-linked on iOS');
      }
    });
  });

  group('Email action configs point at the real app IDs', () {
    test('androidPackageName matches the installed applicationId', () {
      final appId = androidApplicationId();
      expect(AuthService.emailVerificationSettings.androidPackageName, appId);
      expect(AuthService.passwordResetSettings.androidPackageName, appId);
    });

    test('iOSBundleId matches the Xcode Runner bundle identifier', () {
      final bundleIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(
        bundleIds,
        contains(AuthService.emailVerificationSettings.iOSBundleId),
        reason: 'iOSBundleId in ActionCodeSettings does not exist in the '
            'Xcode project — email links would not reopen the iOS app.',
      );
    });

    test('resend-login-link inline config uses the same IDs', () {
      final appId = androidApplicationId();
      expect(
        checkEmailScreen.contains("androidPackageName: '$appId'"),
        isTrue,
        reason: 'check_email_screen.dart duplicates ActionCodeSettings; its '
            'androidPackageName drifted from the applicationId.',
      );
      expect(
        checkEmailScreen.contains("iOSBundleId: '$appId'"),
        isTrue,
        reason: 'check_email_screen.dart iOSBundleId drifted.',
      );
    });
  });

  group('Custom URL schemes and package visibility', () {
    test('inneru:// scheme is registered on both platforms', () {
      expect(infoPlist.contains('<string>inneru</string>'), isTrue,
          reason: 'inneru scheme missing from Info.plist CFBundleURLTypes');
      expect(manifest.contains('android:scheme="inneru"'), isTrue,
          reason: 'inneru scheme missing from AndroidManifest intent filters');
    });

    test('Spotify is queryable on both platforms', () {
      expect(infoPlist.contains('<string>spotify</string>'), isTrue,
          reason: 'spotify missing from LSApplicationQueriesSchemes');
      expect(
        manifest.contains('<package android:name="com.spotify.music" />'),
        isTrue,
        reason: 'Spotify package visibility missing on Android — '
            'authorizeAndConnect would fail only on Android.',
      );
    });
  });

  group('Permission parity (feature-by-feature)', () {
    const pairs = <String, String>{
      // Android permission -> iOS usage description that unlocks the same UX.
      'android.permission.CAMERA': 'NSCameraUsageDescription',
      'android.permission.ACCESS_FINE_LOCATION':
          'NSLocationWhenInUseUsageDescription',
      'android.permission.ACTIVITY_RECOGNITION': 'NSMotionUsageDescription',
      'android.permission.POST_NOTIFICATIONS':
          'NSUserNotificationsUsageDescription',
    };

    pairs.forEach((androidPermission, iosKey) {
      test('$androidPermission <-> $iosKey', () {
        expect(manifest.contains(androidPermission), isTrue,
            reason: '$androidPermission missing on Android but the matching '
                'iOS capability ($iosKey) exists');
        expect(infoPlist.contains(iosKey), isTrue,
            reason: '$iosKey missing on iOS but the matching Android '
                'permission ($androidPermission) exists');
      });
    });

    test('exact alarms are permitted on Android (notification timeliness)',
        () {
      expect(
        manifest.contains('android.permission.SCHEDULE_EXACT_ALARM'),
        isTrue,
        reason: 'Without SCHEDULE_EXACT_ALARM, fasting/meditation/sleep '
            'alarms silently fall back to inexact on Android 12+ and can '
            'arrive very late, while iOS fires them on time.',
      );
    });
  });

  group('Apple Watch companion app', () {
    test('watch app is embedded and tied to the iOS app bundle ID', () {
      final runnerTarget =
          nativeTargetBlock('97C146ED1CF9000F007C117D', 'Runner');
      expect(
        runnerTarget.contains(
          'productType = "com.apple.product-type.application";',
        ),
        isTrue,
        reason: 'Runner must remain a normal iOS app target.',
      );
      expect(
        pbxproj.contains('InnerUWatch.app in Embed Watch Content'),
        isTrue,
        reason: 'Runner must embed InnerUWatch.app or the Apple Watch app '
            'will not ship inside the iOS build.',
      );
      expect(
        pbxproj.contains('dstPath = Watch;') &&
            pbxproj.contains('dstSubfolderSpec = 1;'),
        isTrue,
        reason: 'The Watch app must be copied into Runner.app/Watch so '
            'TestFlight/App Store Connect detects Apple Watch support.',
      );
      expect(
        watchInfoPlist.contains(
          '<key>WKCompanionAppBundleIdentifier</key>',
        ),
        isTrue,
        reason: 'The Watch app must declare its companion iOS app.',
      );
      expect(
        watchInfoPlist.contains('<key>WKApplication</key>') &&
            watchInfoPlist.contains('<true/>'),
        isTrue,
        reason: 'App Store Connect requires WKApplication=true in the '
            'embedded Watch app Info.plist.',
      );
      expect(
        watchInfoPlist.contains('<string>com.valenin.inneru</string>'),
        isTrue,
        reason: 'The Watch companion bundle ID must match Runner.',
      );
      expect(
        pbxproj.contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.valenin.inneru.watchkitapp;',
        ),
        isTrue,
        reason: 'The Watch target needs its own App Store bundle ID.',
      );
    });

    test('watch app has an App Store-valid icon asset catalog', () {
      final appIconSet = Directory(
        'ios/InnerUWatch/Assets.xcassets/AppIcon.appiconset',
      );
      expect(appIconSet.existsSync(), isTrue,
          reason: 'The Watch app needs its own AppIcon asset catalog.');
      expect(
        watchInfoPlist.contains('<key>CFBundleIconName</key>') &&
            watchInfoPlist.contains('<string>AppIcon</string>'),
        isTrue,
        reason: 'App Store Connect requires CFBundleIconName for the '
            'embedded Watch app.',
      );
      expect(
        pbxproj.contains('Assets.xcassets in Resources'),
        isTrue,
        reason: 'The Watch asset catalog must be in the Watch target '
            'Resources phase.',
      );
      expect(
        pbxproj.contains('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'),
        isTrue,
        reason: 'The Watch target must compile the AppIcon asset catalog.',
      );
      expect(
        File('${appIconSet.path}/Icon-App-1024x1024@1x.png').existsSync(),
        isTrue,
        reason: 'The Watch app needs a marketing icon for App Store upload.',
      );
    });

    test('release signing uses the Watch App Store profile', () {
      expect(
        pbxproj.contains('"CODE_SIGN_IDENTITY[sdk=watchos*]" = '
            '"Apple Distribution";'),
        isTrue,
        reason: 'Watch release builds should use Apple Distribution signing.',
      );
      expect(
        pbxproj.contains('"PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*]" = '
            '"InnerU Watch App Store";'),
        isTrue,
        reason: 'Watch release builds need the App Store profile for '
            'com.valenin.inneru.watchkitapp.',
      );
    });
  });
}
