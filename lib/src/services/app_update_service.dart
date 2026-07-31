import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:selfcare_projects/src/services/api_client.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({required this.isOutdated, this.storeUrl});

  final bool isOutdated;
  final String? storeUrl;

  static const AppUpdateCheckResult upToDate =
      AppUpdateCheckResult._(isOutdated: false);

  factory AppUpdateCheckResult.outdated(String storeUrl) {
    return AppUpdateCheckResult._(isOutdated: true, storeUrl: storeUrl);
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final response = await ApiClient.instance
          .getJson('/api/app-version')
          .timeout(const Duration(seconds: 5));

      final packageInfo = await PackageInfo.fromPlatform();

      return evaluate(
        response: response,
        isIOS: Platform.isIOS,
        installedVersion: packageInfo.version,
        installedBuildNumber: packageInfo.buildNumber,
      );
    } catch (error, stack) {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: false);
      return AppUpdateCheckResult.upToDate;
    }
  }

  static AppUpdateCheckResult evaluate({
    required Map<String, dynamic> response,
    required bool isIOS,
    required String installedVersion,
    required String installedBuildNumber,
  }) {
    if (isIOS) {
      final iosRaw = response['ios'];
      final ios =
          iosRaw is Map<String, dynamic> ? iosRaw : null;

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
          ? AppUpdateCheckResult.outdated(storeUrl)
          : AppUpdateCheckResult.upToDate;
    }

    final androidRaw = response['android'];
    final android =
        androidRaw is Map<String, dynamic> ? androidRaw : null;

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
        ? AppUpdateCheckResult.outdated(storeUrl)
        : AppUpdateCheckResult.upToDate;
  }

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
