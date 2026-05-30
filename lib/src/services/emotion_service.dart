import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmotionSaveResult {
  const EmotionSaveResult({
    required this.created,
    required this.emotion,
  });

  final bool created;
  final String? emotion;
}

class EmotionService {
  EmotionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String todayKey([DateTime? now]) => dateKeyFor(now ?? DateTime.now());

  static String dateKeyFor(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Stream<String?> watchTodayEmotion(String userId, {DateTime? now}) {
    return _todayEmotionQuery(userId, now: now).snapshots().map(
          _readEmotionFromSnapshot,
        );
  }

  Future<String?> fetchTodayEmotion(String userId, {DateTime? now}) async {
    final snapshot = await _todayEmotionQuery(userId, now: now).get();
    return _readEmotionFromSnapshot(snapshot);
  }

  Future<EmotionSaveResult> saveTodayEmotion({
    required User user,
    required String emotion,
    required String username,
    DateTime? now,
  }) async {
    final today = dateKeyFor(now ?? DateTime.now());
    final existingSnapshot = await _todayEmotionQuery(user.uid, now: now).get();

    if (existingSnapshot.docs.isNotEmpty) {
      return EmotionSaveResult(
        created: false,
        emotion: _readEmotionFromSnapshot(existingSnapshot),
      );
    }

    await _firestore.collection('emotions').add({
      'userId': user.uid,
      'username': username.trim().isEmpty ? 'Unknown' : username.trim(),
      'emotion': emotion,
      'date': today,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return EmotionSaveResult(created: true, emotion: emotion);
  }

  Query<Map<String, dynamic>> _todayEmotionQuery(String userId,
      {DateTime? now}) {
    return _firestore
        .collection('emotions')
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: dateKeyFor(now ?? DateTime.now()))
        .limit(1);
  }

  String? _readEmotionFromSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return _normalizeEmotion(snapshot.docs.first.data()['emotion']);
  }

  String? _normalizeEmotion(dynamic value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
