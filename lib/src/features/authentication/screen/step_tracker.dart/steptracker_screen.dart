import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
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
    await _requestPermission();
    await _loadSteps();
    _initStepCounter();
  }

  Future<void> _loadSteps() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String? lastSavedDate = prefs.getString('last_saved_date');

    // If the last saved date is not today, reset steps
    if (lastSavedDate != today) {
      int previousSteps = prefs.getInt('saved_steps') ?? 0;

      // Save yesterday's steps to Firestore before resetting
      await _saveDailyStepsToHistory(previousSteps, lastSavedDate);

      // Reset steps and update last saved date
      await prefs.setInt('saved_steps', 0);
      await prefs.setInt('initial_steps', -1); // Reset initial steps
      await prefs.setString('last_saved_date', today);

      _steps = 0;
      _initialSteps = -1;
    } else {
      _steps = prefs.getInt('saved_steps') ?? 0; // Load today's saved steps
    }

    _updateStepCount(_steps);
  }

  Future<void> _requestPermission() async {
    PermissionStatus status = await Permission.activityRecognition.request();

    if (status.isGranted) {
      print('Permission granted!');
    } else if (status.isDenied) {
      print('Permission denied. Ask user to enable it manually.');
      openAppSettings();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  Future<void> _saveDailyStepsToHistory(int steps, String? date) async {
    if (date == null) return;

    String userId = FirebaseAuth.instance.currentUser!.uid;
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    await firestore
        .collection('steps')
        .doc(userId)
        .collection('tracking')
        .doc(date)
        .set({
      'steps': steps,
      'timestamp': DateTime.parse(date).millisecondsSinceEpoch,
    });

    print("Saved $steps steps for $date");
  }

  void _initStepCounter() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _initialSteps = prefs.getInt('initial_steps') ?? -1;

    _stepCountStream = Pedometer.stepCountStream.listen(
      (StepCount event) async {
        int currentSteps = event.steps;

        if (_initialSteps == -1 || currentSteps < _initialSteps) {
          // Ensure initialSteps is always valid
          _initialSteps = currentSteps;
          await prefs.setInt('initial_steps', _initialSteps);
        }

        int newSteps = currentSteps - _initialSteps;

        // Prevent negative step count
        if (newSteps < 0) newSteps = 0;

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
    if (!mounted) return; // Prevent updates if widget is disposed

    SharedPreferences prefs = await SharedPreferences.getInstance();

    setState(() {
      _isWalking = newSteps > _steps;
      _steps = newSteps;
    });

    await prefs.setInt('saved_steps', _steps);
    await prefs.setInt('initial_steps', _initialSteps);

    _stepStreamController.add(_steps);

    if (_steps >= 5000) {
      await _saveDailyActivity(steps: true);
    }

    if (_isWalking) {
      if (_lottieController.isAnimating == false && mounted) {
        _lottieController.repeat();
      }
    } else {
      if (mounted) {
        _lottieController.stop();
        _lottieController.animateTo(0,
            duration: const Duration(milliseconds: 500));
      }
    }
  }

  Future<void> _saveDailyActivity(
      {bool meditation = false, bool steps = false}) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    FirebaseFirestore firestore = FirebaseFirestore.instance;

    // Fetch username from Firestore user document
    DocumentSnapshot userDoc =
        await firestore.collection('users').doc(userId).get();
    String? username = userDoc.exists ? userDoc.get('username') : null;

    if (username != null) {
      String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Use UID for document ID
      DocumentReference docRef =
          firestore.collection('dailytracker').doc('$userId-$formattedDate');

      // Use Firestore's FieldValue.merge to update without overwriting other fields
      await docRef.set({
        'userId': userId,
        'username': username,
        'date': formattedDate,
        if (meditation) 'meditation': true,
        if (steps) 'steps': true,
      }, SetOptions(merge: true));

      print(
          "Updated Firestore: Meditation = $meditation, Steps = $steps, for userId: $userId, username: $username");
    } else {
      print("Error: Username not found for userId: $userId");
    }
  }

  void _setWalkingState(bool isWalking) {
    if (isWalking) {
      _lottieController.forward(); // Start animation smoothly
    } else {
      _lottieController.stop();
    }
  }

  Future<void> _saveStepCompletion() async {
    await _saveDailyActivity(steps: true);
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
                _lottieController.value =
                    0; // Ensures it starts from frame 0 (idle)
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
                    builder: (context) => const TrackingScreen(title: ''),
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
