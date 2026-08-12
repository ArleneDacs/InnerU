import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/pending_sync_retry_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AppSession(
    id: 42,
    token: 'pending-sync-token',
    name: 'Queue User',
    email: 'queue@example.com',
    role: 'user',
    isCoach: false,
  );

  group('PendingSyncRetryCoordinator', () {
    test('rejects a non-positive timer interval', () {
      expect(
        () => PendingSyncRetryCoordinator(
          sessionProvider: () => null,
          sessionStream: const Stream<AppSession?>.empty(),
          retryInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('does not flush while signed out, then flushes after session restore',
        () async {
      AppSession? currentSession;
      final sessions = StreamController<AppSession?>.broadcast();
      final coordinator = PendingSyncRetryCoordinator(
        sessionProvider: () => currentSession,
        sessionStream: sessions.stream,
        retryInterval: const Duration(days: 1),
      );
      var flushCount = 0;
      String? flushedUserId;

      coordinator.registerExerciseSync((userId) async {
        flushCount++;
        flushedUserId = userId;
      });
      coordinator.start();
      await Future<void>.delayed(Duration.zero);

      expect(flushCount, 0);

      currentSession = session;
      sessions.add(session);
      await Future<void>.delayed(Duration.zero);

      expect(flushCount, 1);
      expect(flushedUserId, '42');

      await coordinator.dispose();
      await sessions.close();
    });

    test('coalesces concurrent lifecycle and connectivity retry signals',
        () async {
      final sessions = StreamController<AppSession?>.broadcast();
      final completion = Completer<void>();
      final started = Completer<void>();
      final coordinator = PendingSyncRetryCoordinator(
        sessionProvider: () => session,
        sessionStream: sessions.stream,
        retryInterval: const Duration(days: 1),
      );
      var flushCount = 0;

      coordinator.register('exercise', (userId) async {
        flushCount++;
        started.complete();
        await completion.future;
      });
      coordinator.start();
      await started.future;

      final onResume = coordinator.onConnectivityRestored();
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final manualRetry = coordinator.retryNow();
      await Future<void>.delayed(Duration.zero);

      expect(flushCount, 1);
      completion.complete();
      await Future.wait<void>([onResume, manualRetry]);

      await coordinator.dispose();
      await sessions.close();
    });

    test('retains a failed queue retry and continues with other queues',
        () async {
      final sessions = StreamController<AppSession?>.broadcast();
      final coordinator = PendingSyncRetryCoordinator(
        sessionProvider: () => session,
        sessionStream: sessions.stream,
        retryInterval: const Duration(days: 1),
      );
      var succeedingFlushCount = 0;

      coordinator.register('failing', (userId) async {
        throw StateError('offline');
      });
      coordinator.register('succeeding', (userId) async {
        succeedingFlushCount++;
      });
      coordinator.start();
      await coordinator.retryNow();

      expect(succeedingFlushCount, 1);

      await coordinator.dispose();
      await sessions.close();
    });

    test('retries on a timer fallback while a signed-in session remains',
        () async {
      final sessions = StreamController<AppSession?>.broadcast();
      final coordinator = PendingSyncRetryCoordinator(
        sessionProvider: () => session,
        sessionStream: sessions.stream,
        retryInterval: const Duration(milliseconds: 10),
      );
      var flushCount = 0;

      coordinator.register('exercise', (userId) async {
        flushCount++;
      });
      coordinator.start();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(flushCount, greaterThanOrEqualTo(2));

      await coordinator.dispose();
      await sessions.close();
    });
  });
}
