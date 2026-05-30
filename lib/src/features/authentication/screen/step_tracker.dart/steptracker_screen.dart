import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lottie/lottie.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_goal_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_map_tracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/utils/responsive.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({super.key});

  @override
  State<StepTracker> createState() => _StepTrackerState();
}

class _StepTrackerState extends State<StepTracker>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _lottieController;
  late StreamController<int> _stepStreamController;
  StreamSubscription<StepCount>? _stepCountStream;

  int _steps = 0;
  int _initialSteps = -1;
  int _lastSteps = 0;
  int _lastSyncedStepCount = -1;
  int _dailyGoal = 5000;
  int _lastRawStepCount = 0;
  bool _isWalking = false;
  bool _stepCounterInitialized = false;
  bool _isDisposed = false;
  Timer? _checkTimer;

  // iOS exposes motion access as sensors, while Android uses activity recognition.
  Permission get _stepPermission =>
      Platform.isIOS ? Permission.sensors : Permission.activityRecognition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lottieController = AnimationController(vsync: this);
    _stepStreamController = StreamController<int>.broadcast();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final hasPermission = await _requestPermission();
    await _loadDailyGoal();
    await _loadSteps();
    if (hasPermission) {
      _initStepCounter();
    }
  }

  Future<void> _loadDailyGoal() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    if (user == null) {
      setState(() {
        _dailyGoal = 5000;
      });
      return;
    }

    final cachedGoal = prefs.getInt('daily_step_goal_${user.uid}');
    if (cachedGoal != null && cachedGoal > 0) {
      setState(() {
        _dailyGoal = cachedGoal;
      });
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final dynamic rawGoal = userDoc.data()?['dailyStepGoal'];
      final int? remoteGoal = rawGoal is int ? rawGoal : null;

      if (remoteGoal != null && remoteGoal > 0 && mounted) {
        setState(() {
          _dailyGoal = remoteGoal;
        });
        await prefs.setInt('daily_step_goal_${user.uid}', remoteGoal);
      }
    } catch (error) {
      debugPrint("Failed to load step goal: $error");
    }
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
    _lastRawStepCount = _steps;

    _updateStepCount(_steps);
  }

  Future<bool> _requestPermission() async {
    PermissionStatus status = await _stepPermission.status;
    if (!status.isGranted) {
      status = await _stepPermission.request();
    }

    if (status.isGranted) {
      debugPrint('Step tracking permission granted.');
      return true;
    }

    debugPrint('Step tracking permission not granted: $status');
    return false;
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
    if (_stepCounterInitialized) return;
    _stepCounterInitialized = true;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    _initialSteps = prefs.getInt('initial_steps') ?? -1;

    _stepCountStream = Pedometer.stepCountStream.listen(
      (StepCount event) async {
        if (!mounted || _isDisposed) return;

        int currentSteps = event.steps;

        if (_initialSteps == -1 || currentSteps < _initialSteps) {
          // Ensure initialSteps is always valid
          _initialSteps = currentSteps;
          await prefs.setInt('initial_steps', _initialSteps);
          if (!mounted || _isDisposed) return;
        }

        int newSteps = currentSteps - _initialSteps;

        // Prevent negative step count
        if (newSteps < 0) newSteps = 0;

        if (newSteps != _lastRawStepCount) {
          _handleRawStepCount(newSteps);
        }
      },
      onError: (error) {
        debugPrint("Step counter error: $error");
      },
    );

    _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _isDisposed) return;

      if (_steps == _lastSteps) {
        _setWalkingState(false);
      }
      _lastSteps = _steps;
    });
  }

  void _updateStepCount(int newSteps) async {
    if (!mounted || _isDisposed) {
      return; // Prevent updates if widget is disposed
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted || _isDisposed) return;

    setState(() {
      _isWalking = newSteps > _steps;
      _steps = newSteps;
    });

    await prefs.setInt('saved_steps', _steps);
    await prefs.setInt('initial_steps', _initialSteps);
    if (!mounted || _isDisposed) return;

    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(_steps);
    }

    if (_shouldSyncProgress()) {
      await _syncStepProgress();
    }

    if (_steps >= _dailyGoal) {
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
        'stepCount': _steps,
        'stepGoal': _dailyGoal,
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
    if (!mounted || _isDisposed) return;

    if (isWalking) {
      _lottieController.forward(); // Start animation smoothly
    } else {
      _lottieController.stop();
    }
  }

  void _handleRawStepCount(int rawSteps) {
    if (!mounted || _isDisposed) return;

    final delta = rawSteps - _lastRawStepCount;
    _lastRawStepCount = rawSteps;

    if (delta <= 0) {
      return;
    }

    _updateStepCount(rawSteps);
  }

  Future<void> _syncStepProgress() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      await FirebaseFirestore.instance
          .collection('dailytracker')
          .doc('$userId-$formattedDate')
          .set({
        'stepCount': _steps,
        'stepGoal': _dailyGoal,
        'date': formattedDate,
      }, SetOptions(merge: true));
      _lastSyncedStepCount = _steps;
    } catch (error) {
      debugPrint("Failed to sync step progress: $error");
    }
  }

  bool _shouldSyncProgress() {
    if (_lastSyncedStepCount == -1) return true;
    if (_steps == 0) return true;
    if (_steps >= _dailyGoal && _lastSyncedStepCount < _dailyGoal) return true;
    return (_steps - _lastSyncedStepCount).abs() >= 50;
  }

  Future<void> _openGoalScreen() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => StepGoalScreen(initialGoal: _dailyGoal),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _dailyGoal = result;
      });
      await _syncStepProgress();
    }
  }

  Future<void> _resumeStepCounterIfNeeded() async {
    if (!mounted || _stepCounterInitialized) return;

    final hasPermission = await _requestPermission();
    if (!mounted || !hasPermission) return;

    _initStepCounter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeStepCounterIfNeeded();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stepCountStream?.cancel();
    _checkTimer?.cancel();
    _stepStreamController.close();
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress =
        _dailyGoal <= 0 ? 0 : (_steps / _dailyGoal).clamp(0, 1).toDouble();
    final animationSize =
        context.isTabletWidth ? 360.0 : context.screenWidth * 0.7;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            vertical: context.responsiveValue(20),
          ),
          child: ResponsiveContent(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset(
                  'assets/images/walking.json',
                  width: animationSize.clamp(220, 360),
                  height: animationSize.clamp(220, 360),
                  controller: _lottieController,
                  repeat: false,
                  onLoaded: (composition) {
                    _lottieController.duration = composition.duration;
                    _lottieController.value = 0;
                  },
                ),
                SizedBox(height: context.responsiveValue(10)),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Today ',
                      style: TextStyle(
                        fontSize: context.responsiveFont(15),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      DateFormat('(MMM dd, yyyy)').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: context.responsiveFont(15),
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.responsiveValue(10)),
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
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 5,
                        children: [
                          Text(
                            '${snapshot.data ?? 0}',
                            style: TextStyle(
                              fontSize: context.responsiveFont(60,
                                  min: 0.8, max: 1.15),
                              fontFamily: 'ralemed',
                              color: Colors.white,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: context.responsiveValue(8),
                            ),
                            child: Text(
                              'steps',
                              style: TextStyle(
                                fontSize: context.responsiveFont(22),
                                fontFamily: 'ralemed',
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                SizedBox(height: context.responsiveValue(10)),
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.symmetric(
                    horizontal: context.isTabletWidth ? 20 : 0,
                  ),
                  padding: EdgeInsets.all(context.responsiveValue(18)),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCF5EA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.flag_rounded,
                            color: Color(0xFFCE8F5A),
                          ),
                          SizedBox(width: context.responsiveValue(10)),
                          Expanded(
                            child: Text(
                              'Daily Goal: $_dailyGoal steps',
                              style: TextStyle(
                                fontSize: context.responsiveFont(17),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _openGoalScreen,
                            child: const Text('Set Goal'),
                          ),
                        ],
                      ),
                      SizedBox(height: context.responsiveValue(8)),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: progress,
                          backgroundColor: Colors.white,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF8BC074),
                          ),
                        ),
                      ),
                      SizedBox(height: context.responsiveValue(10)),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 8,
                        spacing: 16,
                        children: [
                          Text('$_steps / $_dailyGoal'),
                          Text('${(progress * 100).round()}% complete'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: context.responsiveValue(16)),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const TrackingScreen(title: ''),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFce8f5a),
                        padding: EdgeInsets.symmetric(
                          horizontal: context.responsiveValue(20),
                          vertical: context.responsiveValue(12),
                        ),
                      ),
                      child: Text(
                        'View Steps',
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: context.responsiveFont(16),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StepMapTrackerScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Track on Map'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
