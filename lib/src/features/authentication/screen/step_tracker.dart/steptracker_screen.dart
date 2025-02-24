import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/tracking.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({super.key});

  @override
  State<StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<StepTracker>
    with SingleTickerProviderStateMixin {
  late AnimationController _lottieController;
  late StreamController<int> _stepStreamController;
  StreamSubscription<StepCount>? _stepSubscription;

  int _steps = 0;
  int _lastRecordedSteps = 0;
  DateTime? _lastStepTime;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    _stepStreamController = StreamController<int>.broadcast();

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSteps();
    await _requestPermission();
  }

  Future<void> _loadSteps() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      setState(() {
        _steps = prefs.getInt('saved_steps') ?? 0;
        _lastRecordedSteps = _steps;
      });
    } catch (e) {
      debugPrint("Error loading steps: $e");
    }
  }

  Future<void> _requestPermission() async {
    var status = await Permission.activityRecognition.request();
    if (status.isGranted) {
      _initPedometer();
    } else {
      debugPrint("Activity Recognition Permission Denied.");
    }
  }

  void _initPedometer() {
    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepError,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("Pedometer Initialization Error: $e");
    }
  }

  void _onStepCount(StepCount event) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      DateTime now = DateTime.now();
      int newSteps = event.steps;

      if (newSteps > _lastRecordedSteps) {
        int stepDiff = newSteps - _lastRecordedSteps;
        setState(() {
          _steps += stepDiff;
          _lastRecordedSteps = newSteps;
          _lastStepTime = now;
        });

        _stepStreamController.add(_steps);
        await prefs.setInt('saved_steps', _steps);

        _startWalkingAnimation();
      }
    } catch (e) {
      debugPrint("Step Count Processing Error: $e");
    }
  }

  void _startWalkingAnimation() {
    if (!_lottieController.isAnimating) {
      _lottieController.repeat();
    }
  }

  void _stopWalkingAnimation() {
    if (_lottieController.isAnimating) {
      _lottieController.stop();
    }
  }

  void _onStepError(error) {
    debugPrint("Step Count Error: $error");
  }

  @override
  void dispose() {
    _lottieController.dispose();
    _stepSubscription?.cancel();
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Today ',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                Text(
                  DateFormat('(MMM dd, yyyy)').format(DateTime.now()),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            StreamBuilder<int>(
              stream: _stepStreamController.stream,
              initialData: _steps,
              builder: (context, snapshot) {
                return ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF8bc074), Color(0xFFce8f5a)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      TweenAnimationBuilder<int>(
                        duration: const Duration(milliseconds: 500),
                        tween: IntTween(begin: 0, end: snapshot.data ?? 0),
                        builder: (context, value, child) {
                          return Text(
                            '$value',
                            style: const TextStyle(
                              fontSize: 60,
                              fontFamily: 'ralemed',
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'steps',
                        style: TextStyle(
                          fontSize: 22,
                          fontFamily: 'ralemed',
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => TrackingScreen(title: '',)),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFce8f5a),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                'View Steps',
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
