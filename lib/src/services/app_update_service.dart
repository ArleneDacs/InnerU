import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:selfcare_projects/src/services/api_client.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({
    required this.isOutdated,
    required this.isRequired,
    this.storeUrl,
  });

  final bool isOutdated;
  final bool isRequired;
  final String? storeUrl;

  /// A newer release exists but the user may keep using the app for now.
  bool get isOptional => isOutdated && !isRequired;

  static const AppUpdateCheckResult upToDate =
      AppUpdateCheckResult._(isOutdated: false, isRequired: false);

  /// [isRequired] deliberately defaults to true. That keeps clients safe
  /// while they are rolling out against an older API that has no
  /// `is_required` field yet, and preserves the app's prior forced-update
  /// behaviour until an administrator explicitly makes a release optional.
  factory AppUpdateCheckResult.outdated(
    String storeUrl, {
    bool isRequired = true,
  }) {
    return AppUpdateCheckResult._(
      isOutdated: true,
      isRequired: isRequired,
      storeUrl: storeUrl,
    );
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  Future<AppUpdateCheckResult> checkForUpdate() async {
    // Store builds are relevant only to the two mobile platforms. Web and
    // desktop receive code through their own deployment/update mechanisms;
    // trying to send them to an iOS/Android store would be misleading.
    if (kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      return AppUpdateCheckResult.upToDate;
    }

    try {
      return await _fetchAndEvaluate().timeout(const Duration(seconds: 5));
    } catch (error, stack) {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: false);
      return AppUpdateCheckResult.upToDate;
    }
  }

  Future<AppUpdateCheckResult> _fetchAndEvaluate() async {
    final response = await ApiClient.instance.getJson('/api/app-version');
    final packageInfo = await PackageInfo.fromPlatform();

    return evaluate(
      response: response,
      isIOS: Platform.isIOS,
      installedVersion: packageInfo.version,
      installedBuildNumber: packageInfo.buildNumber,
    );
  }

  static AppUpdateCheckResult evaluate({
    required Map<String, dynamic> response,
    required bool isIOS,
    required String installedVersion,
    required String installedBuildNumber,
  }) {
    if (isIOS) {
      final iosRaw = response['ios'];
      final ios = iosRaw is Map<String, dynamic> ? iosRaw : null;

      if (ios == null) {
        return AppUpdateCheckResult.upToDate;
      }

      final latestVersionRaw = ios['latest_version'];
      final latestVersion =
          latestVersionRaw is String ? latestVersionRaw : null;

      final storeUrlRaw = ios['store_url'];
      final storeUrl = storeUrlRaw is String ? storeUrlRaw : null;

      if (latestVersion == null || storeUrl == null) {
        return AppUpdateCheckResult.upToDate;
      }

      return _isVersionBehind(installedVersion, latestVersion)
          ? AppUpdateCheckResult.outdated(
              storeUrl,
              isRequired: _isUpdateRequired(ios['is_required']),
            )
          : AppUpdateCheckResult.upToDate;
    }

    final androidRaw = response['android'];
    final android = androidRaw is Map<String, dynamic> ? androidRaw : null;

    if (android == null) {
      return AppUpdateCheckResult.upToDate;
    }

    final latestVersionCodeRaw = android['latest_version_code'];
    final installedCode = int.tryParse(installedBuildNumber);
    final latestCode = latestVersionCodeRaw is int
        ? latestVersionCodeRaw
        : int.tryParse(latestVersionCodeRaw?.toString() ?? '');

    final storeUrlRaw = android['store_url'];
    final storeUrl = storeUrlRaw is String ? storeUrlRaw : null;

    if (installedCode == null || latestCode == null || storeUrl == null) {
      return AppUpdateCheckResult.upToDate;
    }

    return installedCode < latestCode
        ? AppUpdateCheckResult.outdated(
            storeUrl,
            isRequired: _isUpdateRequired(android['is_required']),
          )
        : AppUpdateCheckResult.upToDate;
  }

  /// Old deployed API versions do not contain this field. Treating its
  /// absence (or an invalid value) as required is the safe, backwards-
  /// compatible choice: an outdated client never gains a bypass merely
  /// because its backend rollout has not finished yet.
  static bool _isUpdateRequired(Object? value) => value is bool ? value : true;

  static bool _isVersionBehind(String installed, String latest) {
    final installedParts =
        installed.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final latestParts =
        latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = installedParts.length > latestParts.length
        ? installedParts.length
        : latestParts.length;

    for (var i = 0; i < length; i++) {
      final a = i < installedParts.length ? installedParts[i] : 0;
      final b = i < latestParts.length ? latestParts[i] : 0;
      if (a != b) {
        return a < b;
      }
    }
    return false;
  }
}
