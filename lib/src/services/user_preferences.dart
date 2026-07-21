import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences {
  static const String _keyUsername = "username"; // Key for storing username

  static String _usernameKey(String userId) => "username_$userId";
  static String _favoriteSongKey(String accountKey) =>
      "favoriteSong_$accountKey";
  static String _favoriteSongSourceKey(String accountKey) =>
      "favoriteSongSource_$accountKey";
  static String _favoriteSpotifyUrlKey(String accountKey) =>
      "favoriteSpotifyUrl_$accountKey";

  // Save the currently logged-in username
  static Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  static Future<void> saveUsernameForUser(
      String userId, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey(userId), username);
    await prefs.setString(_keyUsername, username);
  }

  // Load the currently logged-in username
  static Future<String?> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  static Future<String?> loadUsernameForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey(userId));
  }

  // Save favorite song associated with an account-specific key.
  static Future<void> saveFavoriteSong(String accountKey, String song) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoriteSongKey(accountKey), song);
  }

  // Load favorite song based on an account-specific key.
  static Future<String?> loadFavoriteSong(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_favoriteSongKey(accountKey));
  }

  static Future<void> saveFavoriteSongSource(
    String accountKey,
    String source,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoriteSongSourceKey(accountKey), source);
  }

  static Future<String?> loadFavoriteSongSource(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_favoriteSongSourceKey(accountKey));
  }

  static Future<void> saveFavoriteSpotifyUrl(
    String accountKey,
    String spotifyUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoriteSpotifyUrlKey(accountKey), spotifyUrl);
  }

  static Future<String?> loadFavoriteSpotifyUrl(String accountKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_favoriteSpotifyUrlKey(accountKey));
  }
}
