import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';

class Meditation extends StatefulWidget {
  const Meditation({super.key});

  @override
  State<Meditation> createState() => _MeditationState();
}

class _MeditationState extends State<Meditation> {
  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text("Meditation"),
        leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.arrow_back)),
        actions: [IconButton(onPressed: () {}, icon: Icon(Icons.menu))],
      ),
      body: Center(
        child: Container(
          margin: EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset('assets/images/meditation-freepik.png'),
              SizedBox(height: 0), // Reduce spacing
              Center(
                child: GestureDetector(
                  onTap: () => _showTimePicker(context, timeProvider),
                  child: Text(
                    _formatTime(timeProvider.remainingTime),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 55),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: () {},
                      icon: GestureDetector(
                        onTap: timeProvider.isRunning
                            ? timeProvider.pauseTimer
                            : timeProvider.startTimer,
                        child: Icon(
                          color: Color(0xFFCE8F5A),
                          timeProvider.isRunning
                              ? Icons.pause
                              : Icons.play_arrow,
                          size: 40,
                        ),
                      )),
                  IconButton(
                      onPressed: () {},
                      icon: GestureDetector(
                        onTap: timeProvider.stopTimer,
                        child: Icon(
                          color: Color(0xFFCE8F5A),
                          Icons.stop,
                          size: 40,
                        ),
                      )),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.music_note,
                        size: 20,
                      )),
                  Text("A Rainy Day")
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showTimePicker(BuildContext context, TimeProvider timeProvider) {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SizedBox(
            height: 300,
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hms,
              initialTimerDuration:
                  Duration(seconds: timeProvider.remainingTime),
              onTimerDurationChanged: (Duration newDuration) {
                if (newDuration.inSeconds > 0) {
                  timeProvider.setTime(newDuration.inSeconds);
                }
              },
            ),
          );
        });
  }

  String _formatTime(int totalSecond) {
    int hours = totalSecond ~/ 3600;
    int minutes = (totalSecond % 3600) ~/ 60;
    int seconds = totalSecond % 60;
    return "${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }
}
