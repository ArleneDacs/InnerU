import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';

void main() {
  group('AppUpdateService.evaluate — iOS version comparison', () {
    test('reports outdated when installed version is behind', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.1.0',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
      expect(result.storeUrl, 'https://apps.apple.com/app/id1');
    });

    test('reports up to date when versions are equal', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.4',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('reports up to date when installed version is newer', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.0',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.1.0',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('handles mismatched segment counts', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.4.1',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
    });

    test('fails open when the ios payload is missing fields', () {
      final result = AppUpdateService.evaluate(
        response: {'ios': <String, dynamic>{}},
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });
  });

  group('AppUpdateService.evaluate — Android build number comparison', () {
    test('reports outdated when installed build number is behind', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 40,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
    });

    test('reports up to date when build numbers match', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 34,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('fails open when installed build number is not numeric', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 40,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: 'not-a-number',
      );

      expect(result.isOutdated, isFalse);
    });

    test('fails open when the android payload is missing fields', () {
      final result = AppUpdateService.evaluate(
        response: {'android': <String, dynamic>{}},
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });
  });
}
