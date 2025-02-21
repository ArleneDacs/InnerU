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
  void _fetchEmotions() async {
    User? user = _auth.currentUser;
    if (user == null) {
      print("❌ User not logged in.");
      return;
    }

    try {
      // Query Firestore for the user's emotions
      final querySnapshot = await _firestore
          .collection('emotions')
          .where('userId', isEqualTo: user.uid)
          .get();

      // Check if any records were found
      print("📊 Found ${querySnapshot.docs.length} records in Firestore");

      Map<DateTime, String> emotionsData = {};
      DateTime today = _normalizeDate(DateTime.now());
      String? todayEmotion;

      for (var doc in querySnapshot.docs) {
        var data = doc.data();
        String? firestoreDate = data['date'];
        String emotionType = data['emotion'] ?? 'Unknown';

        // Ensure the date from Firestore is parsed correctly
        if (firestoreDate != null) {
          DateTime normalizedDate = _parseFirestoreDate(firestoreDate);

          print(
              "📅 Firestore Record: ${firestoreDate} → Normalized: $normalizedDate, Emotion: $emotionType");

          emotionsData[normalizedDate] = emotionType;

          // Check if the emotion is for today
          if (normalizedDate.isAtSameMomentAs(today)) {
            todayEmotion = emotionType;
            print("✅ Found Emotion for Today: $todayEmotion");
          }
        } else {
          print("⚠️ Firestore record has no 'date' field");
        }
      }

      setState(() {
        _emotionsByDay = emotionsData;
        _todayEmotion = todayEmotion;
      });

      print("🔵 Final Today's Emotion: $_todayEmotion");
      print("📌 All Emotions in Calendar: $_emotionsByDay");
    } catch (e) {
      print("❌ Error fetching emotions from Firestore: $e");
    }
  }

  /// Convert Firestore string date (e.g. '2025-02-20') to DateTime
  DateTime _parseFirestoreDate(String dateString) {
    try {
      // Assumes Firestore date is in 'YYYY-MM-DD' format
      DateTime parsedDate = DateTime.parse(dateString);
      return _normalizeDate(parsedDate);
    } catch (e) {
      print("❌ Error parsing date: $dateString, $e");
      return DateTime.now(); // Fallback to today's date
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
                "No emotion logged for today",
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
