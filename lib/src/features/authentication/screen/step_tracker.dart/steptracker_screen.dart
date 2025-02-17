import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class StepTracker extends StatefulWidget {
  const StepTracker({super.key});

  @override
  State<StepTracker> createState() => _TrackingStepsState();
}

class _TrackingStepsState extends State<StepTracker>
    with SingleTickerProviderStateMixin {
  late AnimationController _lottieController;
  bool isPlaying = true; // Track if animation is playing

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  void _toggleAnimation() {
    setState(() {
      if (isPlaying) {
        _lottieController.stop(); // Pause animation
      } else {
        _lottieController.repeat(); // Resume animation
      }
      isPlaying = !isPlaying;
    });
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
                _lottieController
                  ..duration = composition.duration
                  ..repeat(); // Auto-play on load
              },
            ),
            const SizedBox(height: 50),
            const Text(
              '0 Steps',
              style: TextStyle(
                fontSize: 50,
                fontFamily: 'ralemed',
                fontStyle: FontStyle.italic,
                color: Color(0xFF8bc074),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _toggleAnimation,
              child: Text(isPlaying ? "Pause" : "Play"),
            ),
          ],
        ),
      ),
    );
  }
}
