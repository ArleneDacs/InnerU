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

  // Variables for week selection based on the current month
  List<String> _weeks = [];
  String? _selectedWeek;
  DateTime _focusedMonth = DateTime.now(); // Track the focused month

  @override
  void initState() {
    super.initState();
    _fetchEmotions();
    _updateWeeksForMonth(
        _focusedMonth.month); // Initialize weeks for the current month
  }

  /// Fetch emotions from Firestore and update calendar
  void _fetchEmotions() async {
    User? user = _auth.currentUser;
    if (user == null) {
      print("❌ User not logged in.");
      return;
    }

    try {
      final querySnapshot = await _firestore
          .collection('emotions')
          .where('userId', isEqualTo: user.uid)
          .get();

      Map<DateTime, String> emotionsData = {};
      DateTime today = _normalizeDate(DateTime.now());
      String? todayEmotion;

      for (var doc in querySnapshot.docs) {
        var data = doc.data();
        String? firestoreDate = data['date'];
        String emotionType = data['emotion'] ?? 'Unknown';

        if (firestoreDate != null) {
          DateTime normalizedDate = _parseFirestoreDate(firestoreDate);
          emotionsData[normalizedDate] = emotionType;

          if (normalizedDate.isAtSameMomentAs(today)) {
            todayEmotion = emotionType;
          }
        }
      }

      setState(() {
        _emotionsByDay = emotionsData;
        _todayEmotion = todayEmotion;
      });
    } catch (e) {
      print("❌ Error fetching emotions from Firestore: $e");
    }
  }

  void _showEmotionMessage(BuildContext context, String emotion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Emotion of the Day"),
        content: Text(
          "You felt $emotion on this day! ${_getEmojiForEmotion(emotion)}",
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          ),
        ],
      ),
    );
  }

  DateTime _parseFirestoreDate(String dateString) {
    try {
      DateTime parsedDate = DateTime.parse(dateString);
      return _normalizeDate(parsedDate);
    } catch (e) {
      return DateTime.now(); // Fallback to today's date
    }
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

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

  /// Update the list of weeks based on the focused month
  void _updateWeeksForMonth(int month) {
    List<String> weeks = [];
    // Example week ranges per month
    weeks.add('Week 1: 1-$month to 9-$month');
    weeks.add('Week 2: 10-$month to 16-$month');
    weeks.add('Week 3: 17-$month to 23-$month');
    weeks.add('Week 4: 24-$month to 31-$month');

    setState(() {
      _weeks = weeks;
      _selectedWeek = _weeks.first; // Default to the first week
    });
  }

  /// Stress Analysis based on emotion logs for the selected week
  void _analyzeStressForWeek(String selectedWeek) {
    RegExp weekRegExp = RegExp(r'(\d+)-(\d+) to (\d+)-(\d+)');
    Match? match = weekRegExp.firstMatch(selectedWeek);
    if (match != null) {
      int startDay = int.parse(match.group(1)!);
      int startMonth = _focusedMonth.month;
      int endDay = int.parse(match.group(3)!);
      int endMonth = _focusedMonth.month;

      DateTime startDate = DateTime(DateTime.now().year, startMonth, startDay);
      DateTime endDate = DateTime(DateTime.now().year, endMonth, endDay);

      int stressCount = 0;
      int totalDays = 0;
      _emotionsByDay.forEach((date, emotion) {
        if (date.isAfter(startDate.subtract(Duration(days: 1))) &&
            date.isBefore(endDate.add(Duration(days: 1)))) {
          if (emotion == 'sad' || emotion == 'angry' || emotion == 'neutral') {
            stressCount++;
          }
          totalDays++;
        }
      });

      String analysisMessage;
      if (totalDays == 0) {
        analysisMessage = 'No emotions were logged for this week.';
      } else {
        double stressPercentage = (stressCount / totalDays) * 100;
        if (stressPercentage > 50) {
          analysisMessage =
              'Your stress level for this week is very high. Consider meditation or sharing your thoughts with a community.';
        } else if (stressPercentage > 25) {
          analysisMessage =
              'You had a moderate level of stress this week. Keep an eye on your emotions and practice mindfulness.';
        } else {
          analysisMessage =
              'Your stress level for this week was low. Keep up the good work maintaining emotional balance!';
        }
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Stress Analysis for $selectedWeek"),
          content: Text(analysisMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
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

            // Dropdown for selecting week within the selected month
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: DropdownButton<String>(
                value: _selectedWeek,
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedWeek = newValue;
                    _analyzeStressForWeek(
                        _selectedWeek!); // Analyze stress for the selected week
                  });
                },
                items: _weeks.map((String week) {
                  return DropdownMenuItem<String>(
                    value: week,
                    child: Text(week),
                  );
                }).toList(),
              ),
            ),

            // Calendar
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TableCalendar(
                  focusedDay: _focusedMonth,
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  calendarStyle: CalendarStyle(
                    markersMaxCount: 0,
                    todayDecoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, date, _) {
                      DateTime normalizedDate = _normalizeDate(date);
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
                  onDaySelected: (selectedDay, focusedDay) {
                    DateTime normalizedDate = _normalizeDate(selectedDay);
                    if (_emotionsByDay.containsKey(normalizedDate)) {
                      String emotion = _emotionsByDay[normalizedDate]!;
                      _showEmotionMessage(context, emotion);
                    } else {
                      _showEmotionMessage(
                          context, "No emotion recorded for this day.");
                    }
                  },
                  onPageChanged: (focusedDay) {
                    setState(() {
                      _focusedMonth = focusedDay;
                      _updateWeeksForMonth(_focusedMonth
                          .month); // Update the weeks based on new month
                    });
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
