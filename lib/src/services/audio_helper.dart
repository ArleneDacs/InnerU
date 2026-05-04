import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AudioHelper {
  static final AudioPlayer _audioPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  static String? playingSong;

  static Future<void> playSong(String songTitle, String assetPath,
      Function(String?) onStateChange) async {
    try {
      // Always stop and reset, even if the same song
      await _audioPlayer.stop();
      await _audioPlayer.release();
      await Future.delayed(const Duration(milliseconds: 300));

      print("Starting new audio: $assetPath");
      await _audioPlayer.play(AssetSource(assetPath));
      await _audioPlayer.resume();

      playingSong = songTitle;
      onStateChange(playingSong);
    } catch (e) {
      print("Error playing song: $e");
      playingSong = null;
      onStateChange(null);
    }
  }

  static Future<void> togglePlayPause(String songTitle, String assetPath,
      Function(String?) onStateChange) async {
    if (playingSong == songTitle) {
      await _audioPlayer.pause();
      playingSong = null;
    } else {
      await playSong(songTitle, assetPath, onStateChange);
    }
  }

  static Future<void> stopAudio() async {
    await _audioPlayer.stop();
    playingSong = null;
  }
}
