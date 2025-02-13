import 'package:audioplayers/audioplayers.dart';

class AudioHelper {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static String? playingSong; // Track currently playing song

  static Future<void> togglePlayPause(String songTitle, String assetPath,
      Function(String?) onStateChange) async {
    if (playingSong == songTitle) {
      await _audioPlayer.pause();
      playingSong = null;
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(assetPath));
      playingSong = songTitle;
    }
    onStateChange(playingSong);
  }
}
