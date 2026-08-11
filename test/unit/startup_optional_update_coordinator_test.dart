import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';
import 'package:selfcare_projects/src/services/startup_optional_update_coordinator.dart';

void main() {
  group('StartupOptionalUpdateCoordinator', () {
    final optional = AppUpdateCheckResult.outdated(
      'https://apps.apple.com/app/id1',
      isRequired: false,
    );

    test('queues and consumes one optional update once', () {
      final coordinator = StartupOptionalUpdateCoordinator();

      expect(coordinator.queue(optional), isTrue);
      expect(coordinator.hasPending, isTrue);
      expect(coordinator.consume(), same(optional));
      expect(coordinator.hasShown, isTrue);
      expect(coordinator.hasPending, isFalse);
    });

    test('rejects duplicate, required, and already-consumed prompts', () {
      final coordinator = StartupOptionalUpdateCoordinator();
      final required = AppUpdateCheckResult.outdated(
        'https://apps.apple.com/app/id1',
      );

      expect(coordinator.queue(required), isFalse);
      expect(coordinator.queue(optional), isTrue);
      expect(coordinator.queue(optional), isFalse);
      coordinator.consume();
      expect(coordinator.queue(optional), isFalse);
      expect(coordinator.consume(), isNull);
    });
  });
}
