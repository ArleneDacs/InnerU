import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shimmer/shimmer.dart';

class EmotionTrackerPage extends StatefulWidget {
  @override
  _EmotionTrackerPageState createState() => _EmotionTrackerPageState();
}

class _EmotionTrackerPageState extends State<EmotionTrackerPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<DateTime, String> _emotionsByDay = {};
  String? _todayEmotion;

  List<String> _weeks = [];
  String? _selectedWeek;
  DateTime _focusedMonth = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEmotions();
    _updateWeeksForMonth(_focusedMonth.month);
  }

  void _fetchEmotions() async {
    User? user = _auth.currentUser;
    if (user == null) {
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
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching emotions: $e");
    }
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _parseFirestoreDate(String dateString) {
    try {
      return _normalizeDate(DateTime.parse(dateString));
    } catch (e) {
      return DateTime.now();
    }
  }

  void _updateWeeksForMonth(int month) {
    DateTime now = DateTime.now();
    int year = now.year;

    int lastDay = DateTime(year, month + 1, 1).subtract(Duration(days: 1)).day;

    List<String> weeks = [
      'Week 1: ${_formatDate(DateTime(year, month, 1))} to ${_formatDate(DateTime(year, month, 9))}',
      'Week 2: ${_formatDate(DateTime(year, month, 10))} to ${_formatDate(DateTime(year, month, 16))}',
      'Week 3: ${_formatDate(DateTime(year, month, 17))} to ${_formatDate(DateTime(year, month, 23))}',
      'Week 4: ${_formatDate(DateTime(year, month, 24))} to ${_formatDate(DateTime(year, month, lastDay))}',
    ];

    setState(() {
      _weeks = weeks;
      _selectedWeek = null;
    });
  }

  String _formatDate(DateTime date) {
    return "${_getMonthName(date.month)} ${date.day}";
  }

  String _getMonthName(int month) {
    List<String> months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];
    return months[month - 1];
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

  void _analyzeStressForWeek(String selectedWeek) {
    RegExp weekRegExp = RegExp(r'(\w+) (\d+) to (\w+) (\d+)');
    Match? match = weekRegExp.firstMatch(selectedWeek);

    if (match != null) {
      String startMonthName = match.group(1)!;
      int startDay = int.parse(match.group(2)!);
      String endMonthName = match.group(3)!;
      int endDay = int.parse(match.group(4)!);

      int startMonth = _getMonthIndex(startMonthName);
      int endMonth = _getMonthIndex(endMonthName);

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

  int _getMonthIndex(String monthName) {
    List<String> months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December"
    ];
    return months.indexOf(monthName) + 1;
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Column(
                  children: [
                    Container(
                        height: 60,
                        width: double.infinity,
                        color: Colors.white),
                    SizedBox(height: 20),
                    Container(
                        height: 50,
                        width: double.infinity,
                        color: Colors.white),
                    SizedBox(height: 20),
                    Expanded(
                      child: Container(
                          width: double.infinity, color: Colors.white),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (_todayEmotion != null) ...[
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Today's Emotion: ",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _getEmojiForEmotion(_todayEmotion!) +
                                  " " +
                                  _todayEmotion!,
                              style: TextStyle(fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: DropdownButton<String>(
                          value: _selectedWeek,
                          hint: Text("Select a week"),
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedWeek = newValue;
                              });
                              _analyzeStressForWeek(newValue);
                            }
                          },
                          items: _weeks.map((String week) {
                            return DropdownMenuItem<String>(
                              value: week,
                              child: Text(week),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    Expanded(
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: TableCalendar(
                            focusedDay: _focusedMonth,
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2030, 12, 31),
                            calendarStyle: CalendarStyle(
                              markersMaxCount: 0,
                              todayDecoration: BoxDecoration(
                                color: Colors.teal,
                                shape: BoxShape.circle,
                              ),
                            ),
                            calendarBuilders: CalendarBuilders(
                              defaultBuilder: (context, date, _) {
                                DateTime normalizedDate = _normalizeDate(date);
                                if (_emotionsByDay
                                    .containsKey(normalizedDate)) {
                                  String emotion =
                                      _emotionsByDay[normalizedDate]!;
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
                              DateTime normalizedDate =
                                  _normalizeDate(selectedDay);
                              if (_emotionsByDay.containsKey(normalizedDate)) {
                                String emotion =
                                    _emotionsByDay[normalizedDate]!;
                                _showEmotionMessage(context, emotion);
                              } else {
                                _showEmotionMessage(context,
                                    "No emotion recorded for this day.");
                              }
                            },
                            onPageChanged: (focusedDay) {
                              setState(() {
                                _focusedMonth = focusedDay;
                                _updateWeeksForMonth(_focusedMonth.month);
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
