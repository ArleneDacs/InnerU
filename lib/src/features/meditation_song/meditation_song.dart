import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';

class MeditationSong extends StatefulWidget {
  const MeditationSong({super.key});

  @override
  State<MeditationSong> createState() => _MeditationSongState();
}

class _MeditationSongState extends State<MeditationSong>
    with WidgetsBindingObserver {
  int? isLikedIndex;
  int? playingIndex;
  final AudioPlayer _audioPlayer = AudioPlayer(); // Local AudioPlayer instance

  final List<Map<String, String>> songs = [
    {
      "title": "Under the Shining Sun",
      "assetImage": "assets/images/forest_birds.jpg",
      "assetPath": "audio/Forest_Birds.mp3"
    },
    {
      "title": "Call of the Waves",
      "assetImage": "assets/images/ocean_waves.jpg",
      "assetPath": "audio/Ocean_Waves.mp3"
    },
    {
      "title": "It's Raining Gently",
      "assetImage": "assets/images/rain.jpg",
      "assetPath": "audio/Rain_Sounds.mp3"
    },
    {
      "title": "Beside the Fireplace",
      "assetImage": "assets/images/night_firepit.jpg",
      "assetPath": "audio/Night_Firepit.mp3"
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLikedSong();
  }

  /// Detect when the app is backgrounded or exited
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _stopAudio(); // Stop when the app goes into the background
    }
  }

  /// Load liked song from SharedPreferences and find its index
  Future<void> _loadLikedSong() async {
    String? username = await UserPreferences.loadUsername();
    if (username != null) {
      String? savedSong = await UserPreferences.loadFavoriteSong(username);
      if (savedSong != null) {
        int index = songs.indexWhere((song) => song["title"] == savedSong);
        setState(() {
          isLikedIndex = index != -1 ? index : null;
        });
      }
    }
  }

  Future<void> _saveLikedSong(int? index) async {
    String? username = await UserPreferences.loadUsername();
    if (username != null) {
      setState(() {
        isLikedIndex = index;
      });

      if (index != null) {
        await UserPreferences.saveFavoriteSong(
            username, songs[index]["title"]!);
      } else {
        await UserPreferences.saveFavoriteSong(
            username, 'No favorite song yet.');
      }
    }
  }

  /// Stop music when the user leaves the page
  void _stopAudio() {
    AudioHelper.stopAudio(); // Stop playback when user exits or navigates away
    setState(() {
      playingIndex = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAudio(); // Stop playback when leaving the page
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Music Player")),
      body: Column(
        children: [
          Image.asset('assets/images/naive-dance-sticker-set.png'),
          const Text("SONG PREVIEWS", style: TextStyle(fontSize: 20)),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                bool isPlaying = playingIndex == index;
                bool isLiked = isLikedIndex == index;

                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(songs[index]["assetImage"]!,
                        width: 50, height: 50, fit: BoxFit.cover),
                  ),
                  title: Text(songs[index]["title"]!,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () {
                          AudioHelper.togglePlayPause(
                            songs[index]["title"]!,
                            songs[index]["assetPath"]!,
                            (song) {
                              setState(() {
                                playingIndex = song == null ? null : index;
                              });
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.star : Icons.star_border_outlined,
                          color: isLiked ? Colors.amber : null,
                        ),
                        onPressed: () async {
                          await _saveLikedSong(isLiked ? null : index);
                          if (!isLiked) {
                            Navigator.pop(context, songs[index]["title"]!);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
