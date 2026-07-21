import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UserPreferences username', () {
    test('saves and loads the current username', () async {
      await UserPreferences.saveUsername('karina');
      expect(await UserPreferences.loadUsername(), 'karina');
    });

    test('returns null when no username stored', () async {
      expect(await UserPreferences.loadUsername(), isNull);
    });

    test('saves a per-user username and updates the current one', () async {
      await UserPreferences.saveUsernameForUser('uid-1', 'karina');
      await UserPreferences.saveUsernameForUser('uid-2', 'anna');

      expect(await UserPreferences.loadUsernameForUser('uid-1'), 'karina');
      expect(await UserPreferences.loadUsernameForUser('uid-2'), 'anna');
      expect(await UserPreferences.loadUsername(), 'anna');
    });
  });

  group('UserPreferences favorite song', () {
    test('stores favorites per account without cross-talk', () async {
      await UserPreferences.saveFavoriteSong('acct-1', 'Calm Waters');
      await UserPreferences.saveFavoriteSong('acct-2', 'Deep Focus');
      await UserPreferences.saveFavoriteSongSource('acct-1', 'local');
      await UserPreferences.saveFavoriteSpotifyUrl(
        'acct-1',
        'https://open.spotify.com/track/abc',
      );

      expect(await UserPreferences.loadFavoriteSong('acct-1'), 'Calm Waters');
      expect(await UserPreferences.loadFavoriteSong('acct-2'), 'Deep Focus');
      expect(await UserPreferences.loadFavoriteSongSource('acct-1'), 'local');
      expect(await UserPreferences.loadFavoriteSongSource('acct-2'), isNull);
      expect(
        await UserPreferences.loadFavoriteSpotifyUrl('acct-1'),
        'https://open.spotify.com/track/abc',
      );
      expect(await UserPreferences.loadFavoriteSpotifyUrl('acct-2'), isNull);
    });
  });
}
