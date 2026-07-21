import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';

void main() {
  group('TimeProvider', () {
    test('starts with the default 30-minute meditation time', () {
      final provider = TimeProvider();
      expect(provider.remainingTime, 30 * 60);
      expect(provider.initialTime, 30 * 60);
      expect(provider.isRunning, isFalse);
    });

    test('setTime updates remaining and initial time and notifies', () {
      final provider = TimeProvider();
      var notified = 0;
      provider.addListener(() => notified++);

      provider.setTime(300);

      expect(provider.remainingTime, 300);
      expect(provider.initialTime, 300);
      expect(notified, 1);
    });

    test('startTimer counts down once per second', () {
      fakeAsync((async) {
        final provider = TimeProvider();
        provider.setTime(10);

        provider.startTimer();
        expect(provider.isRunning, isTrue);

        async.elapse(const Duration(seconds: 3));
        expect(provider.remainingTime, 7);

        async.elapse(const Duration(seconds: 4));
        expect(provider.remainingTime, 3);
        expect(provider.isRunning, isTrue);
      });
    });

    test('startTimer is idempotent while already running', () {
      fakeAsync((async) {
        final provider = TimeProvider();
        provider.setTime(10);

        provider.startTimer();
        async.elapse(const Duration(seconds: 2));
        provider.startTimer(); // must not create a second timer

        async.elapse(const Duration(seconds: 2));
        expect(provider.remainingTime, 6);
      });
    });

    test('does not start when remaining time is zero', () {
      final provider = TimeProvider();
      provider.setTime(0);
      provider.startTimer();
      expect(provider.isRunning, isFalse);
    });
  });
}
