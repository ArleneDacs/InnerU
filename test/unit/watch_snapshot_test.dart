import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/watch_snapshot.dart';

void main() {
  group('WatchSnapshot', () {
    test('merge stores values and data returns them', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100, 'mood': 'happy'});
      expect(snapshot.data['steps'], 100);
      expect(snapshot.data['mood'], 'happy');
    });

    test('merge drops null values but keeps existing keys', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100});
      snapshot.merge({'steps': null, 'stepGoal': 5000});
      expect(snapshot.data['steps'], 100);
      expect(snapshot.data['stepGoal'], 5000);
    });

    test('merge overwrites existing values', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 100});
      snapshot.merge({'steps': 250});
      expect(snapshot.data['steps'], 250);
    });

    test('data is unmodifiable', () {
      final snapshot = WatchSnapshot();
      snapshot.merge({'steps': 1});
      expect(() => snapshot.data['steps'] = 2, throwsUnsupportedError);
    });
  });

  group('dayKey', () {
    test('formats with zero padding', () {
      expect(dayKey(DateTime(2026, 7, 6)), '2026-07-06');
      expect(dayKey(DateTime(2026, 11, 23)), '2026-11-23');
    });
  });

  group('StepSyncGate', () {
    final t0 = DateTime(2026, 7, 16, 12, 0, 0);

    test('first call always syncs', () {
      final gate = StepSyncGate();
      expect(gate.shouldSync(10, t0), isTrue);
    });

    test('small delta within interval does not sync', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(15, t0.add(const Duration(seconds: 10))), isFalse);
    });

    test('delta of 10 or more syncs', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(20, t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('small delta after 30 seconds syncs', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      expect(gate.shouldSync(11, t0.add(const Duration(seconds: 30))), isTrue);
    });

    test('gate rebases after a granted sync', () {
      final gate = StepSyncGate();
      gate.shouldSync(10, t0);
      gate.shouldSync(20, t0.add(const Duration(seconds: 10)));
      expect(
        gate.shouldSync(25, t0.add(const Duration(seconds: 15))),
        isFalse,
      );
    });
  });
}
