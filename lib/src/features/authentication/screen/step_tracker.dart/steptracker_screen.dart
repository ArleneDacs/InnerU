import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({super.key});

  @override
  State<StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<StepTracker>
    with SingleTickerProviderStateMixin {
  late AnimationController _lottieController;
  late StreamController<int> _stepStreamController;
  late StreamSubscription<StepCount> _stepSubscription;

  int _steps = 0;
  DateTime? _lastStepTime;
  Timer? _monitoringTimer;

  Future<void> _loadSteps() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _steps = prefs.getInt('saved_steps') ?? 0;
    });
  }

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    _stepStreamController = StreamController<int>.broadcast();

    _loadSteps();
    _requestPermission();
    _initMotionTracking();

    // 🔥 Start monitoring user movement instantly
    _startMonitoring();
  }

  Future<void> _requestPermission() async {
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      await Permission.activityRecognition.request();
    }
    _initPedometer();
  }

  void _initPedometer() {
    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepError,
      );
    } catch (e) {
      print("Pedometer Error: $e");
    }
  }

  void _onStepCount(StepCount event) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    int newSteps = event.steps;
    DateTime now = DateTime.now();

    if (newSteps > _steps) {
      int stepDiff = newSteps - _steps;
      _steps = newSteps;
      _lastStepTime = now;

      _stepStreamController.add(_steps);
      await prefs.setInt('saved_steps', _steps);

      // Start animation immediately
      _startWalkingAnimation(stepDiff);
    }
  }

  void _startWalkingAnimation(int stepDifference) {
    if (!_lottieController.isAnimating) {
      _lottieController.repeat();
    }
  }

  void _stopWalkingAnimation() {
    if (_lottieController.isAnimating) {
      _lottieController.stop();
    }
  }

  void _startMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_lastStepTime != null &&
          DateTime.now().difference(_lastStepTime!).inMilliseconds > 500) {
        _stopWalkingAnimation();
      }
    });
  }

  void _initMotionTracking() {
    accelerometerEvents.listen((AccelerometerEvent event) {
      double totalAcceleration =
          event.x.abs() + event.y.abs() + event.z.abs();

      if (totalAcceleration > 15) {
        _lastStepTime = DateTime.now(); // Update step time
        if (!_lottieController.isAnimating) {
          _lottieController.repeat();
        }
      }
    });
  }

  void _onStepError(error) {
    print("Step Count Error: $error");
  }

  @override
  void dispose() {
    _lottieController.dispose();
    _monitoringTimer?.cancel();
    _stepSubscription.cancel();
    _stepStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/images/walking.json',
              width: 300,
              height: 300,
              controller: _lottieController,
              onLoaded: (composition) {
                _lottieController.duration = composition.duration;
              },
            ),
            const SizedBox(height: 50),
            StreamBuilder<int>(
              stream: _stepStreamController.stream,
              initialData: _steps,
              builder: (context, snapshot) {
                return Text(
                  '${snapshot.data} Steps',
                  style: const TextStyle(
                    fontSize: 50,
                    fontFamily: 'ralemed',
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF8bc074),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
