import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/src/constants/image_strings.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart'; // Import AudioHelper

class Meditation extends StatefulWidget {
  const Meditation({super.key});

  @override
  State<Meditation> createState() => _MeditationState();
}

class _MeditationState extends State<Meditation> {
  String favoriteSong = "No favorite selected";
  String? playingSong; // Track the currently playing song
  String? favoriteSongPath; // Store song file path

  @override
  void initState() {
    super.initState();
    loadFavorite();
  }

  Future<void> loadFavorite() async {
    String? username = await UserPreferences.loadUsername();
    if (username != null) {
      String? song = await UserPreferences.loadFavoriteSong(username);
      if (mounted) {
        setState(() {
          favoriteSong = song ?? "No favorite selected";
          favoriteSongPath = _getSongPath(favoriteSong); // Get the file path
        });
      }
    }
  }

  String? _getSongPath(String songTitle) {
    final songMap = {
      "Under the Shining Sun": "audio/Forest_Birds.mp3",
      "Call of the Waves": "audio/Ocean_Waves.mp3",
      "It's Raining Gently": "audio/Rain_Sounds.mp3",
      "Beside the Fireplace": "audio/Night_Firepit.mp3",
    };
    return songMap[songTitle];
  }

  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);
    return Scaffold(
      body: Center(
        child: Container(
          margin: EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Lottie.asset("assets/images/lottie_meditation.json", height: 300),
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
                      onPressed: () {
                        if (favoriteSongPath != null) {
                          AudioHelper.togglePlayPause(
                            favoriteSong,
                            favoriteSongPath!,
                            (newPlayingSong) {
                              setState(() => playingSong = newPlayingSong);
                            },
                          );
                        }
                        timeProvider.isRunning
                            ? timeProvider.pauseTimer()
                            : timeProvider.startTimer();
                      },
                      icon: Icon(
                        color: Color(0xFFCE8F5A),
                        timeProvider.isRunning ? Icons.pause : Icons.play_arrow,
                        size: 40,
                      )),
                  IconButton(
                      onPressed: () {
                        timeProvider.stopTimer();
                        AudioHelper.togglePlayPause(
                          favoriteSong,
                          favoriteSongPath!,
                          (newPlayingSong) {
                            setState(() => playingSong = null);
                          },
                        );
                      },
                      icon: Icon(
                        color: Color(0xFFCE8F5A),
                        Icons.stop,
                        size: 40,
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
                  Text(favoriteSong)
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
