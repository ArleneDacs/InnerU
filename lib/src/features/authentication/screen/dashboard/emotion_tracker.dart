import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';

class EmotionTrackerPage extends StatefulWidget {
  @override
  _EmotionTrackerPageState createState() => _EmotionTrackerPageState();
}

class _EmotionTrackerPageState extends State<EmotionTrackerPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<DateTime, String> _emotionsByDay = {};
  String? _todayEmotion;

  @override
  void initState() {
    super.initState();
    _fetchEmotions();
  }

  /// Fetch emotions from Firestore and update calendar
  void _fetchEmotions() {
    User? user = _auth.currentUser;
    if (user == null) {
      print("❌ User not logged in.");
      return;
    }

    _firestore
        .collection('emotions')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      Map<DateTime, String> emotionsData = {};
      DateTime today = _normalizeDate(DateTime.now());
      String? todayEmotion;

      print("🔥 Checking Firestore Data for user: ${user.uid}");
      print("📆 Today's normalized date: $today");

      for (var doc in snapshot.docs) {
        var data = doc.data();
        DateTime normalizedDate = _parseFirestoreDate(data['date']);
        String emotionType =
            data['emotion'] != null ? data['emotion'] as String : 'Unknown';

        print(
            "📅 Firestore Record: ${data['date']} → Normalized: $normalizedDate, Emotion: $emotionType");

        emotionsData[normalizedDate] = emotionType;

        // Check if today's emotion exists
        if (normalizedDate.isAtSameMomentAs(today)) {
          todayEmotion = emotionType;
          print("✅ Found Emotion for Today: $todayEmotion");
        }
      }

      setState(() {
        _emotionsByDay = emotionsData;
        _todayEmotion = todayEmotion;
      });

      print("🔵 Final Today's Emotion: $_todayEmotion");
      print("📌 All Emotions in Calendar: $_emotionsByDay");
    });
  }

  /// Convert Firestore string date to DateTime
  DateTime _parseFirestoreDate(String dateString) {
    try {
      DateTime parsedDate = DateTime.parse(dateString);
      return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
    } catch (e) {
      print("❌ Error parsing date: $dateString");
      return DateTime.now();
    }
  }

  /// Normalize DateTime to remove time components
  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get color for emotion type
  Color _getColorForEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return Colors.yellow;
      case 'sad':
        return Colors.blue;
      case 'angry':
        return Colors.red;
      case 'neutral':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Get emoji for emotion type
  String _getEmojiForEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      case 'neutral':
        return '😐';
      default:
        return '❓';
    }
  }

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Emotion Tracker')),
        body: Center(child: Text('User not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Emotion Tracker'),
      ),
      body: Column(
        children: [
          // Display today's emotion
          if (_todayEmotion != null) ...[
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Today's Emotion: ",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _getEmojiForEmotion(_todayEmotion!) + " " + _todayEmotion!,
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Text(
                "No log emotion for today",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey),
              ),
            ),
          ],

          // Calendar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TableCalendar(
                focusedDay: DateTime.now(),
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) {
                    DateTime normalizedDate =
                        DateTime(date.year, date.month, date.day);
                    if (_emotionsByDay.containsKey(normalizedDate)) {
                      String emotion = _emotionsByDay[normalizedDate]!;

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: _getColorForEmotion(emotion),
                              shape: BoxShape.circle,
                            ),
                            width: 35,
                            height: 35,
                          ),
                          Text(
                            _getEmojiForEmotion(emotion),
                            style: TextStyle(fontSize: 18),
                          ),
                        ],
                      );
                    }
                    return null;
                  },
                ),
                calendarStyle: CalendarStyle(
                  markersMaxCount: 0, // Disable default gray markers
                  todayDecoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
