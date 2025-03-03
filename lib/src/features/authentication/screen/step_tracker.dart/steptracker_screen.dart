import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({super.key});

  @override
  State<StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<StepTracker>
    with SingleTickerProviderStateMixin {
  late AnimationController _lottieController;
  late StreamController<int> _stepStreamController;
  StreamSubscription<StepCount>? _stepCountStream;

  int _steps = 0;
  int _initialSteps = -1;
  int _lastSteps = 0;
  bool _isWalking = false;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    _stepStreamController = StreamController<int>.broadcast();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSteps();
    _initStepCounter();
  }

Future<void> _loadSteps() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  _initialSteps = prefs.getInt('initial_steps') ?? -1;

  String? lastSavedDate = prefs.getString('last_saved_date');

  if (lastSavedDate == today) {
    _steps = prefs.getInt('saved_steps') ?? 0; // Load today's saved steps
  } else {
    // Save yesterday's steps before resetting
    int previousSteps = prefs.getInt('saved_steps') ?? 0;
    await _saveDailyStepsToHistory(previousSteps, lastSavedDate);

    // Reset steps for today
    await prefs.setInt('saved_steps', 0);
    await prefs.setString('last_saved_date', today);
    _steps = 0;
  }

  _updateStepCount(_steps);
}




Future<void> _saveDailyStepsToHistory(int steps, String? date) async {
  if (date == null) return;

  String userId = FirebaseAuth.instance.currentUser!.uid; 
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  await firestore.collection('steps').doc(userId).collection('tracking').doc(date).set({
    'steps': steps,
    'timestamp': DateTime.parse(date).millisecondsSinceEpoch, 
  });

  print("Saved $steps steps for $date");
}


void _initStepCounter() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  _initialSteps = prefs.getInt('initial_steps') ?? -1;

  _stepCountStream = Pedometer.stepCountStream.listen(
    (StepCount event) {
      int currentSteps = event.steps;

      if (_initialSteps == -1) {
        _initialSteps = currentSteps;
        prefs.setInt('initial_steps', _initialSteps); 
      }

      int newSteps = currentSteps - _initialSteps;

      if (newSteps != _steps) {
        _updateStepCount(newSteps);
      }
    },
    onError: (error) {
      debugPrint("Step counter error: $error");
    },
  );

  _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
    if (_steps == _lastSteps) {
      _setWalkingState(false);
    }
    _lastSteps = _steps;
  });
}

void _updateStepCount(int newSteps) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  setState(() {
    _isWalking = newSteps > _steps;
    _steps = newSteps;
  });

  // Save steps to SharedPreferences
  await prefs.setInt('saved_steps', _steps);
  await prefs.setInt('initial_steps', _initialSteps);

  _stepStreamController.add(_steps);

  if (_isWalking) {
    _lottieController.repeat();
  } else {
    _lottieController.stop();
    _lottieController.animateTo(0, duration: const Duration(milliseconds: 500));
  }
}


  void _setWalkingState(bool isWalking) {
    if (isWalking) {
      _lottieController.forward(); // Start animation smoothly
    } else {
      _lottieController.stop();
    }
  }

  @override
  void dispose() {
    _lottieController.dispose();
    _stepCountStream?.cancel();
    _stepStreamController.close();
    _checkTimer?.cancel();
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
          repeat: false,
          onLoaded: (composition) {
            _lottieController.duration = composition.duration;
            _lottieController.value = 0; // Ensures it starts from frame 0 (idle)
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
                      Text(
                        '${snapshot.data ?? 0}',
                        style: const TextStyle(
                          fontSize: 60,
                          fontFamily: 'ralemed',
                          color: Colors.white,
                        ),
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
                    builder: (context) => const TrackingScreen(title:''),
                  ),
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
