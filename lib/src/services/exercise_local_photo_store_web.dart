import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'exercise_local_photo_store_base.dart';

ExerciseLocalPhotoStore createExerciseLocalPhotoStore() =>
    _WebExerciseLocalPhotoStore();

class _WebExerciseLocalPhotoStore implements ExerciseLocalPhotoStore {
  static const _referencePrefix = 'exercise-web-photo:';
  static const _keysPrefix = 'exercise_web_photo_keys_';

  String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _keysKey(String userId) => '$_keysPrefix${_safeSegment(userId)}';

  String _photoKey({
    required String userId,
    required String clientSessionId,
    required String slot,
  }) {
    return 'exercise_web_photo_${_safeSegment(userId)}_'
        '${_safeSegment(clientSessionId)}_${_safeSegment(slot)}';
  }

  Future<List<String>> _keys(SharedPreferences prefs, String userId) async {
    return prefs.getStringList(_keysKey(userId)) ?? <String>[];
  }

  @override
  Future<String> save({
    required String userId,
    required String clientSessionId,
    required String slot,
    required Uint8List bytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _photoKey(
      userId: userId,
      clientSessionId: clientSessionId,
      slot: slot,
    );
    final keys = await _keys(prefs, userId);
    if (!keys.contains(key)) {
      keys.add(key);
      await prefs.setStringList(_keysKey(userId), keys);
    }
    await prefs.setString(key, base64Encode(bytes));
    return '$_referencePrefix$key';
  }

  @override
  Future<Uint8List?> read(String reference) async {
    if (!reference.startsWith(_referencePrefix)) return null;
    final key = reference.substring(_referencePrefix.length);
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String reference) async {
    if (!reference.startsWith(_referencePrefix)) return;
    final key = reference.substring(_referencePrefix.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    for (final preferenceKey in prefs.getKeys()) {
      if (!preferenceKey.startsWith(_keysPrefix)) continue;
      final keys = prefs.getStringList(preferenceKey) ?? <String>[];
      if (!keys.contains(key)) continue;
      keys.remove(key);
      if (keys.isEmpty) {
        await prefs.remove(preferenceKey);
      } else {
        await prefs.setStringList(preferenceKey, keys);
      }
      return;
    }
  }

  @override
  Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keysKey(userId);
    final keys = prefs.getStringList(key) ?? <String>[];
    for (final photoKey in keys) {
      await prefs.remove(photoKey);
    }
    await prefs.remove(key);
  }
}
