import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:selfcare_projects/src/services/watch_sync_service.dart';

class EmotionSaveResult {
  const EmotionSaveResult({
    required this.created,
    required this.emotion,
    this.previousEmotion,
  });

  final bool created;
  final String? emotion;
  final String? previousEmotion;
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
    final savedAt = now ?? DateTime.now();
    final today = dateKeyFor(savedAt);
    final normalizedEmotion = _normalizeEmotion(emotion) ?? emotion.trim();
    final normalizedUsername =
        username.trim().isEmpty ? 'Unknown' : username.trim();
    final historyEntry = <String, dynamic>{
      'emotion': normalizedEmotion,
      'loggedAt': Timestamp.fromDate(savedAt),
    };
    final existingSnapshot = await _todayEmotionQuery(user.uid, now: now).get();

    if (existingSnapshot.docs.isNotEmpty) {
      final existingDoc = _latestEmotionDoc(existingSnapshot);
      final previousEmotion = _normalizeEmotion(existingDoc?.data()['emotion']);
      await existingDoc!.reference.set({
        'username': normalizedUsername,
        'emotion': normalizedEmotion,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoggedAt': Timestamp.fromDate(savedAt),
        'history': FieldValue.arrayUnion([historyEntry]),
      }, SetOptions(merge: true));

      WatchSyncService.instance.syncMood(normalizedEmotion, savedAt);

      return EmotionSaveResult(
        created: false,
        emotion: normalizedEmotion,
        previousEmotion: previousEmotion,
      );
    }

    await _firestore.collection('emotions').add({
      'userId': user.uid,
      'username': normalizedUsername,
      'emotion': normalizedEmotion,
      'date': today,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoggedAt': Timestamp.fromDate(savedAt),
      'history': [historyEntry],
    });

    WatchSyncService.instance.syncMood(normalizedEmotion, savedAt);

    return EmotionSaveResult(created: true, emotion: normalizedEmotion);
  }

  Query<Map<String, dynamic>> _todayEmotionQuery(String userId,
      {DateTime? now}) {
    return _firestore
        .collection('emotions')
        .where('userId', isEqualTo: userId)
        .where('date', isEqualTo: dateKeyFor(now ?? DateTime.now()));
  }

  String? _readEmotionFromSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final doc = _latestEmotionDoc(snapshot);
    if (doc == null) {
      return null;
    }
    return _normalizeEmotion(doc.data()['emotion']);
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _latestEmotionDoc(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (snapshot.docs.isEmpty) return null;
    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final aTime = _emotionSortTime(a.data());
        final bTime = _emotionSortTime(b.data());
        return bTime.compareTo(aTime);
      });
    return docs.first;
  }

  int _emotionSortTime(Map<String, dynamic> data) {
    for (final key in ['lastLoggedAt', 'updatedAt', 'createdAt']) {
      final value = data[key];
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is DateTime) return value.millisecondsSinceEpoch;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  String? _normalizeEmotion(dynamic value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }
}
