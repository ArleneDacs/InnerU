import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class TimeProvider extends ChangeNotifier {
  static const int defaultMeditationSeconds = 30 * 60;

  int _remainingTime = defaultMeditationSeconds;
  int _initialTime = defaultMeditationSeconds;
  Timer? _timer;
  bool _isRunning = false;

  int get remainingTime => _remainingTime;
  int get initialTime => _initialTime;
  bool get isRunning => _isRunning;

  void startTimer({VoidCallback? onComplete}) {
    if (_timer != null || _remainingTime == 0) return;
    _isRunning = true;
    WatchSyncService.instance.syncMeditationSession(
      active: true,
      endsAt: DateTime.now().add(Duration(seconds: _remainingTime)),
    );
    _timer = Timer.periodic(
      Duration(seconds: 1),
      (timer) {
        if (_remainingTime > 1) {
          _remainingTime--;
          notifyListeners();
          return;
        }

        _remainingTime = 0;
        _timer?.cancel();
        _timer = null;
        _isRunning = false;
        WatchSyncService.instance.syncMeditationSession(active: false);
        AudioHelper.stopAudio();
        notifyListeners();
        onComplete?.call();
      },
    );
  }

  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    WatchSyncService.instance.syncMeditationSession(active: false);
    AudioHelper.stopAudio();
    notifyListeners();
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _remainingTime = _initialTime;
    _isRunning = false;
    WatchSyncService.instance.syncMeditationSession(active: false);
    AudioHelper.stopAudio();
    notifyListeners();
  }

  void resetForAccountSwitch() {
    _timer?.cancel();
    _timer = null;
    _remainingTime = defaultMeditationSeconds;
    _initialTime = defaultMeditationSeconds;
    _isRunning = false;
    AudioHelper.stopAudio();
    notifyListeners();
  }

  void setTime(int seconds) {
    _remainingTime = seconds;
    _initialTime = seconds;
    notifyListeners();
  }
}
