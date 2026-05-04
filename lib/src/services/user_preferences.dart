import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences {
  static const String _keyUsername = "username"; // Key for storing username

  // Save the currently logged-in username
  static Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
  }

  // Load the currently logged-in username
  static Future<String?> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUsername);
  }

  // Save favorite song associated with the username
  static Future<void> saveFavoriteSong(String username, String song) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("favoriteSong_$username", song);
  }

  // Load favorite song based on the username
  static Future<String?> loadFavoriteSong(String username) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("favoriteSong_$username");
  }
}
