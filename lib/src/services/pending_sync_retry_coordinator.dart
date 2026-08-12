import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

/// A persisted queue's network write for one signed-in user.
typedef PendingSyncFlusher = Future<void> Function(String userId);

/// Retries registered persisted queues when the app has another reasonable
/// chance to reach the server.
///
/// Connectivity packages report only network-interface state and are not
/// currently part of InnerU. This coordinator therefore uses three safe
/// signals instead: a restored/signed-in session, the app returning to the
/// foreground, and a modest timer fallback. Queue implementations remain the
/// source of truth for persistence, idempotency, and retaining failed work.
///
/// Register flushers before [start] during app startup, after authentication
/// has restored its local session. It never invokes a flusher without an
/// active session and collapses overlapping lifecycle/timer/manual triggers
/// into the same retry pass.
class PendingSyncRetryCoordinator with WidgetsBindingObserver {
  PendingSyncRetryCoordinator({
    AppSession? Function()? sessionProvider,
    Stream<AppSession?>? sessionStream,
    Duration retryInterval = defaultRetryInterval,
  })  : _sessionProvider =
            sessionProvider ?? (() => AuthService.instance.currentSession),
        _sessionStream = sessionStream ?? AuthService.instance.sessionStream,
        _retryInterval = retryInterval {
    if (retryInterval <= Duration.zero) {
      throw ArgumentError.value(
        retryInterval,
        'retryInterval',
        'must be greater than zero',
      );
    }
  }

  static const Duration defaultRetryInterval = Duration(minutes: 2);

  static final PendingSyncRetryCoordinator instance =
      PendingSyncRetryCoordinator();

  final AppSession? Function() _sessionProvider;
  final Stream<AppSession?> _sessionStream;
  final Duration _retryInterval;
  final Map<String, PendingSyncFlusher> _flushers =
      <String, PendingSyncFlusher>{};

  StreamSubscription<AppSession?>? _sessionSubscription;
  Timer? _retryTimer;
  Future<void>? _activeRetry;
  bool _started = false;

  @visibleForTesting
  bool get isStarted => _started;

  @visibleForTesting
  bool get isRetrying => _activeRetry != null;

  /// Registers or replaces a named queue flusher.
  ///
  /// A stable [name] makes registration idempotent across startup retries.
  /// Replacing a flusher is useful in tests and during a hot restart; it does
  /// not alter persisted queue data.
  void register(String name, PendingSyncFlusher flush) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }

    _flushers[normalizedName] = flush;
    if (_started && _activeRetry == null && _sessionProvider() != null) {
      unawaited(retryNow());
    }
  }

  /// Convenience registration name for the Exercise offline queue.
  void registerExerciseSync(PendingSyncFlusher flush) {
    register('exercise', flush);
  }

  void unregister(String name) {
    _flushers.remove(name.trim());
  }

  /// Starts session, lifecycle, and periodic retry triggers exactly once.
  void start() {
    if (_started) return;

    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _sessionSubscription = _sessionStream.listen((session) {
      if (session != null) {
        unawaited(retryNow());
      }
    });
    _retryTimer = Timer.periodic(
      _retryInterval,
      (_) => unawaited(retryNow()),
    );

    // Handles a session which was restored before this coordinator started.
    unawaited(retryNow());
  }

  /// Lets a future connectivity listener immediately request a retry without
  /// making this service depend on a particular connectivity plugin.
  Future<void> onConnectivityRestored() => retryNow();

  /// Performs one best-effort pass over all queues for the current session.
  ///
  /// Calls arriving while a pass is already in progress receive the same
  /// future rather than starting duplicate writes. Failed flushes are logged
  /// and left for their queue implementation to retain and retry later.
  Future<void> retryNow() {
    if (!_started || _flushers.isEmpty || _sessionProvider() == null) {
      return Future<void>.value();
    }

    final activeRetry = _activeRetry;
    if (activeRetry != null) return activeRetry;

    final retry = _retryRegisteredQueues();
    _activeRetry = retry;
    return retry.whenComplete(() {
      if (identical(_activeRetry, retry)) {
        _activeRetry = null;
      }
    });
  }

  Future<void> _retryRegisteredQueues() async {
    final initialSession = _sessionProvider();
    if (initialSession == null) return;

    final userId = initialSession.id.toString();
    if (userId.isEmpty) return;

    // Snapshot registrations so a callback can safely register/unregister a
    // different queue. Check the current callback again before invoking it,
    // which honors an unregister that happened while an earlier queue ran.
    final registrations = Map<String, PendingSyncFlusher>.from(_flushers);
    for (final registration in registrations.entries) {
      final currentSession = _sessionProvider();
      if (currentSession == null ||
          currentSession.id != initialSession.id ||
          currentSession.token != initialSession.token) {
        return;
      }
      if (_flushers[registration.key] != registration.value) continue;

      try {
        await registration.value(userId);
      } catch (error) {
        debugPrint('Pending ${registration.key} sync will retry later: $error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(retryNow());
    }
  }

  /// Releases process-local observers. Normal production use keeps the
  /// singleton running; this is primarily useful for controlled teardown.
  Future<void> dispose() async {
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _started = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _flushers.clear();
  }
}
