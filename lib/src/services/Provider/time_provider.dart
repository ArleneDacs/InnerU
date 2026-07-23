import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class TimeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const int defaultMeditationSeconds = 30 * 60;
  static const MethodChannel _keepAwakeChannel =
      MethodChannel('inneru/meditation_keep_awake');

  int _remainingTime = defaultMeditationSeconds;
  int _initialTime = defaultMeditationSeconds;
  Timer? _timer;
  bool _isRunning = false;
  DateTime? _endsAt;
  VoidCallback? _completionCallback;
  bool _keepAwakeEnabled = false;

  int get remainingTime => _remainingTime;
  int get initialTime => _initialTime;
  bool get isRunning => _isRunning;

  TimeProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_setKeepAwake(false));
    super.dispose();
  }

  void startTimer({VoidCallback? onComplete}) {
    if (_timer != null || _remainingTime == 0) return;
    _completionCallback = onComplete;
    _endsAt = DateTime.now().add(Duration(seconds: _remainingTime));
    _isRunning = true;
    WatchSyncService.instance.syncMeditationSession(
      active: true,
      endsAt: _endsAt,
    );
    unawaited(_setKeepAwake(true));
    _timer = Timer.periodic(
      Duration(seconds: 1),
      (_) => _syncCountdownWithClock(),
    );
    _syncCountdownWithClock();
  }

  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _endsAt = null;
    _completionCallback = null;
    WatchSyncService.instance.syncMeditationSession(active: false);
    AudioHelper.stopAudio();
    unawaited(_setKeepAwake(false));
    notifyListeners();
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _remainingTime = _initialTime;
    _isRunning = false;
    _endsAt = null;
    _completionCallback = null;
    WatchSyncService.instance.syncMeditationSession(active: false);
    AudioHelper.stopAudio();
    unawaited(_setKeepAwake(false));
    notifyListeners();
  }

  void resetForAccountSwitch() {
    _timer?.cancel();
    _timer = null;
    _remainingTime = defaultMeditationSeconds;
    _initialTime = defaultMeditationSeconds;
    _isRunning = false;
    _endsAt = null;
    _completionCallback = null;
    AudioHelper.stopAudio();
    unawaited(_setKeepAwake(false));
    notifyListeners();
  }

  void setTime(int seconds) {
    _remainingTime = seconds;
    _initialTime = seconds;
    if (_isRunning) {
      _endsAt = DateTime.now().add(Duration(seconds: seconds));
      WatchSyncService.instance.syncMeditationSession(
        active: true,
        endsAt: _endsAt,
      );
      _syncCountdownWithClock();
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCountdownWithClock();
    }
  }

  Future<void> _setKeepAwake(bool enabled) async {
    if (kIsWeb || _keepAwakeEnabled == enabled) return;
    _keepAwakeEnabled = enabled;
    try {
      await _keepAwakeChannel.invokeMethod<void>(
        'setEnabled',
        {'enabled': enabled},
      );
    } catch (_) {
      _keepAwakeEnabled = !enabled;
    }
  }

  void _syncCountdownWithClock() {
    if (!_isRunning || _endsAt == null) return;

    final remaining = _endsAt!.difference(DateTime.now());
    if (remaining > Duration.zero) {
      final nextRemaining = remaining.inSeconds;
      if (nextRemaining != _remainingTime) {
        _remainingTime = nextRemaining;
        notifyListeners();
      }
      return;
    }

    _remainingTime = 0;
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _endsAt = null;
    WatchSyncService.instance.syncMeditationSession(active: false);
    AudioHelper.stopAudio();
    unawaited(_setKeepAwake(false));
    notifyListeners();

    final callback = _completionCallback;
    _completionCallback = null;
    callback?.call();
  }
}
