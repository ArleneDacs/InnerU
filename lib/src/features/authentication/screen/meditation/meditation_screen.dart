import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/services/Provider/time_provider.dart';
import 'package:selfcare_projects/src/services/audio_helper.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/spotify_native_service.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';

class Meditation extends StatefulWidget {
  const Meditation({super.key});

  @override
  State<Meditation> createState() => _MeditationState();
}

class _MeditationState extends State<Meditation> {
  String favoriteSong = "No favorite selected";
  String favoriteSongSource = "default";
  String? favoriteSpotifyUrl;
  String? favoriteSpotifyTrackId;
  bool _spotifyConnecting = false;
  bool _completionAlertHandled = false;
  String? playingSong;
  String? favoriteSongPath;

  @override
  void initState() {
    super.initState();
    _scheduleDailyMeditationReminder();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadFavorite();
  }

  Future<void> _scheduleDailyMeditationReminder() async {
    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance.scheduleDailyMeditationReminder();
  }

  Future<void> loadFavorite() async {
    final username = await UserPreferences.loadUsername();
    if (username == null) return;

    final song = await UserPreferences.loadFavoriteSong(username);
    final source = await UserPreferences.loadFavoriteSongSource(username);
    final spotifyUrl = await UserPreferences.loadFavoriteSpotifyUrl(username);
    if (!mounted) return;

    setState(() {
      favoriteSong = song ?? "No favorite selected";
      favoriteSongSource = source ?? "default";
      favoriteSpotifyUrl = spotifyUrl;
      favoriteSpotifyTrackId = _extractSpotifyTrackId(spotifyUrl);
      favoriteSongPath = _getSongPath(favoriteSong);
    });
  }

  Future<void> _saveDailyActivity({
    bool meditation = false,
    bool steps = false,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final firestore = FirebaseFirestore.instance;
    final userDoc = await firestore.collection('users').doc(userId).get();
    final username = userDoc.exists ? userDoc.get('username') : null;

    if (username != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docRef =
          firestore.collection('dailytracker').doc('$userId-$formattedDate');

      await docRef.set({
        'userId': userId,
        'username': username,
        'date': formattedDate,
        if (meditation) 'meditation': true,
        if (steps) 'steps': true,
      }, SetOptions(merge: true));
    }
  }

  void _onMeditationComplete() async {
    await _saveDailyActivity(meditation: true);
  }

  Future<void> _scheduleMeditationCompletionAlert(
    TimeProvider timeProvider,
  ) async {
    if (timeProvider.remainingTime <= 0) return;

    _completionAlertHandled = false;
    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance
        .scheduleMeditationCompleteNotification(
      endsAt: DateTime.now().add(Duration(seconds: timeProvider.remainingTime)),
    );
  }

  Future<void> _cancelMeditationCompletionAlert() async {
    await FastingNotificationService.instance
        .cancelMeditationCompleteNotification();
  }

  Future<void> _handleMeditationCompleteAlert() async {
    if (_completionAlertHandled) return;
    _completionAlertHandled = true;

    await FastingNotificationService.instance
        .cancelMeditationCompleteNotification();
    await FastingNotificationService.instance
        .showMeditationCompleteNotification();
  }

  String? _getSongPath(String songTitle) {
    const songMap = {
      "Under the Shining Sun": "audio/Forest_Birds.mp3",
      "Call of the Waves": "audio/Ocean_Waves.mp3",
      "It's Raining Gently": "audio/Rain_Sounds.mp3",
      "Beside the Fireplace": "audio/Night_Firepit.mp3",
    };
    return songMap[songTitle];
  }

  String? _extractSpotifyTrackId(String? spotifyUrl) {
    final uri = Uri.tryParse(spotifyUrl ?? '');
    if (uri == null) return null;

    final segments = uri.pathSegments;
    final trackIndex = segments.indexOf('track');
    if (trackIndex == -1 || trackIndex + 1 >= segments.length) {
      return null;
    }

    return segments[trackIndex + 1];
  }

  Future<void> _pauseSpotifyPlayer() async {
    await SpotifyNativeService.instance.pause();
    if (!mounted) return;
    setState(() {
      playingSong = null;
    });
  }

  Future<void> _stopSpotifyPlayer() async {
    await SpotifyNativeService.instance.stop();
    if (!mounted) return;
    setState(() {
      playingSong = null;
    });
  }

  String? _spotifyUriFromTrackId(String? trackId) {
    final trimmed = trackId?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return 'spotify:track:$trimmed';
  }

  Future<void> _handleMeditationPlay(TimeProvider timeProvider) async {
    if (favoriteSongSource == "spotify" &&
        favoriteSong != "No favorite selected") {
      if (timeProvider.isRunning) {
        timeProvider.pauseTimer();
        await _pauseSpotifyPlayer();
        await _cancelMeditationCompletionAlert();
      } else {
        final trackUri = _spotifyUriFromTrackId(favoriteSpotifyTrackId);
        if (trackUri == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This Spotify track is missing a valid track ID. Please choose another Spotify song.',
              ),
            ),
          );
          return;
        }

        if (mounted) {
          setState(() {
            _spotifyConnecting = true;
          });
        }

        try {
          await _scheduleMeditationCompletionAlert(timeProvider);
          await SpotifyNativeService.instance.playTrack(trackUri);
          timeProvider.startTimer();
          if (!mounted) return;
          setState(() {
            playingSong = favoriteSong;
          });
        } catch (error) {
          await _cancelMeditationCompletionAlert();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Spotify native playback failed. Make sure Spotify is installed, you are logged in, and your account can play this track.\n$error',
              ),
            ),
          );
        } finally {
          if (mounted) {
            setState(() {
              _spotifyConnecting = false;
            });
          }
        }
      }
      return;
    }

    if (favoriteSongPath != null) {
      AudioHelper.togglePlayPause(
        favoriteSong,
        favoriteSongPath!,
        (newPlayingSong) {
          if (!mounted) return;
          setState(() {
            playingSong = newPlayingSong;
          });
        },
      );
    }

    if (timeProvider.isRunning) {
      timeProvider.pauseTimer();
      await _cancelMeditationCompletionAlert();
    } else {
      await _scheduleMeditationCompletionAlert(timeProvider);
      timeProvider.startTimer();
    }
  }

  Future<void> _openMusicSelector() async {
    final selectedSong = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationSong(),
      ),
    );

    if (selectedSong is! Map) return;

    final selectedTitle = (selectedSong['title'] as String?)?.trim();
    final selectedSource = (selectedSong['source'] as String?)?.trim();
    final selectedSpotifyUrl = (selectedSong['spotifyUrl'] as String?)?.trim();
    if (selectedTitle == null || selectedTitle.isEmpty) {
      return;
    }

    await AudioHelper.stopAudio();
    await _stopSpotifyPlayer();
    if (!mounted) return;

    setState(() {
      favoriteSong = selectedTitle;
      favoriteSongSource = selectedSource == "spotify" ? "spotify" : "default";
      favoriteSpotifyUrl =
          selectedSource == "spotify" ? selectedSpotifyUrl : null;
      favoriteSpotifyTrackId = _extractSpotifyTrackId(selectedSpotifyUrl);
      favoriteSongPath = _getSongPath(selectedTitle);
      playingSong = null;
    });
  }

  void _showTimePicker(BuildContext context, TimeProvider timeProvider) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SizedBox(
          height: 300,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hms,
            initialTimerDuration: Duration(seconds: timeProvider.remainingTime),
            onTimerDurationChanged: (Duration newDuration) {
              if (newDuration.inSeconds > 0) {
                timeProvider.setTime(newDuration.inSeconds);
              }
            },
          ),
        );
      },
    );
  }

  String _formatTime(int totalSecond) {
    final hours = totalSecond ~/ 3600;
    final minutes = (totalSecond % 3600) ~/ 60;
    final seconds = totalSecond % 60;
    return "${hours.toString().padLeft(2, "0")}:${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final timeProvider = Provider.of<TimeProvider>(context);

    if (timeProvider.remainingTime == 0 && timeProvider.isRunning) {
      timeProvider.stopTimer();
      _stopSpotifyPlayer();
      _onMeditationComplete();
      _handleMeditationCompleteAlert();
    }

    return Scaffold(
      body: Center(
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 55,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _spotifyConnecting
                      ? null
                      : () => _handleMeditationPlay(timeProvider),
                  icon: Icon(
                    timeProvider.isRunning ? Icons.pause : Icons.play_arrow,
                    color: const Color(0xFFCE8F5A),
                    size: 40,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    timeProvider.stopTimer();
                    AudioHelper.stopAudio();
                    _stopSpotifyPlayer();
                    _cancelMeditationCompletionAlert();
                    setState(() {
                      playingSong = null;
                    });
                  },
                  icon: const Icon(
                    Icons.stop,
                    color: Color(0xFFCE8F5A),
                    size: 40,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.music_note, size: 20),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openMusicSelector,
                  child: Text(
                    '$favoriteSong (${favoriteSongSource == "spotify" ? "Spotify" : "Default"})',
                  ),
                ),
                IconButton(
                  onPressed: null,
                  tooltip: favoriteSongSource == "spotify"
                      ? 'Native Spotify playback is active for this track'
                      : 'Open on Spotify',
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
            if (favoriteSongSource == "spotify" && _spotifyConnecting)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Connecting...',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
