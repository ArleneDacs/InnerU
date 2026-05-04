import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore Import
import 'package:intl/intl.dart'; // For date formatting
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart'; // AudioHelper for music

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadFavorite(); // Reload favorite song when coming back
  }

  /// Load favorite song from user preferences
  Future<void> loadFavorite() async {
    String? username = await UserPreferences.loadUsername();
    if (username != null) {
      String? song = await UserPreferences.loadFavoriteSong(username);
      if (mounted) {
        setState(() {
          favoriteSong = song ?? "No favorite selected";
          favoriteSongPath = _getSongPath(favoriteSong); // Get file path
        });
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

  void _onMeditationComplete() async {
    await _saveDailyActivity(meditation: true);
  }

  /// Get file path based on song title
  String? _getSongPath(String songTitle) {
    final songMap = {
      "Under the Shining Sun": "audio/Forest_Birds.mp3",
      "Call of the Waves": "audio/Ocean_Waves.mp3",
      "It's Raining Gently": "audio/Rain_Sounds.mp3",
      "Beside the Fireplace": "audio/Night_Firepit.mp3",
    };
    return songMap[songTitle];
  }

  /// Save meditation session to Firestore in "dailytracker" collection

  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);

    /// Auto-save when time reaches 0
    if (timeProvider.remainingTime == 0 && timeProvider.isRunning) {
      timeProvider.stopTimer();
      _onMeditationComplete();
    }

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
                      AudioHelper.stopAudio();
                      setState(() {
                        playingSong = null;
                      });

                      // Save session when the timer stops
                      _onMeditationComplete;
                    },
                    icon: Icon(
                      color: Color(0xFFCE8F5A),
                      Icons.stop,
                      size: 40,
                    ),
                  ),
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
                  GestureDetector(
                    onTap: () async {
                      final selectedSong = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => MeditationSong()),
                      );

                      if (selectedSong != null && selectedSong is String) {
                        final newSongPath = _getSongPath(selectedSong);

                        setState(() {
                          favoriteSong = selectedSong;
                          favoriteSongPath = newSongPath;
                        });

                        // ✅ Always play selected song, even if it's the same as the current
                        if (newSongPath != null) {
                          print("Changing music to: $selectedSong");
                          await AudioHelper.playSong(
                            selectedSong,
                            newSongPath,
                            (newPlayingSong) {
                              if (mounted) {
                                setState(() {
                                  playingSong = newPlayingSong;
                                });
                              }
                            },
                          );
                        }
                      }
                    },
                    child: Text(favoriteSong),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  /// Show Timer Picker for user to set meditation time
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

  /// Format time in HH:MM:SS format
  String _formatTime(int totalSecond) {
    int hours = totalSecond ~/ 3600;
    int minutes = (totalSecond % 3600) ~/ 60;
    int seconds = totalSecond % 60;
    return "${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }
}
