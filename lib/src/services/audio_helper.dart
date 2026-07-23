import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AudioHelper {
  static final AudioPlayer _audioPlayer = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer);
  static String? playingSong;
  static bool _audioContextConfigured = false;

  // Without this, meditation audio uses whatever default session the native
  // side falls back to when setAudioContext is never called — which does
  // not keep playing once the screen locks or the app backgrounds, even
  // though Info.plist already declares the "audio" background mode.
  // AVAudioSessionCategory.playback is what actually makes iOS keep the
  // session alive in the background; Android's usage/focus hints do the
  // equivalent for not being killed as a transient sound.
  static Future<void> _ensureAudioContext() async {
    if (_audioContextConfigured) return;
    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      _audioContextConfigured = true;
    } catch (e) {
      print("Error configuring audio context: $e");
    }
  }

  static Future<void> playSong(String songTitle, String assetPath,
      Function(String?) onStateChange) async {
    try {
      await _ensureAudioContext();
      // Always stop and reset, even if the same song
      await _audioPlayer.stop();
      await _audioPlayer.release();
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
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
    await _audioPlayer.setReleaseMode(ReleaseMode.release);
    playingSong = null;
  }
}
