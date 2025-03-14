import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Custom Colors
const customColor1 = Color(0xFF6D849A); // Primary color
const customColor2 = Color(0xFFCE8F5A); // Secondary color
const customColor3 = Color(0xFF90A17D); // Accent color

class UserProgressPage extends StatefulWidget {
  @override
  _UserProgressPageState createState() => _UserProgressPageState();
}

class _UserProgressPageState extends State<UserProgressPage> {
  List<Map<String, dynamic>> users = [];
  Map<String, Map<String, Map<String, bool>>> userProgressData = {};
  String currentUserId = '';
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    fetchCurrentUserId();
  }

  Future<void> fetchCurrentUserId() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        setState(() {
          currentUserId = userDoc['username'];
        });
        fetchUsersAndProgress();
      }
    }
  }

  Future<void> fetchUsersAndProgress() async {
    try {
      QuerySnapshot trackerSnapshot =
          await FirebaseFirestore.instance.collection('dailytracker').get();

      Set<String> uniqueUsernames = {}; // Ensure unique usernames
      Map<String, Map<String, Map<String, bool>>> progressData = {};
      List<Map<String, dynamic>> tempUsers = [];

      for (var doc in trackerSnapshot.docs) {
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;

        // Extract username without the date
        String username = userData['username'] ?? doc.id.split('-').first;

        // Skip the current user
        if (username == currentUserId) continue;

        if (!uniqueUsernames.contains(username)) {
          uniqueUsernames.add(username);
          tempUsers.add({'userId': username, 'username': username});
        }

        String lastUpdated = userData['lastUpdated'] ??
            DateFormat('yyyy-MM-dd').format(DateTime.now());

        progressData.putIfAbsent(username, () => {});
        progressData[username]![lastUpdated] = {
          'Call': userData['call'] ?? false,
          'Steps': userData['steps'] ?? false,
          'Meditation': userData['meditation'] ?? false,
          'Learning': userData['learning'] ?? false,
          'Add Value': userData['addValue'] ?? false,
        };
      }

      setState(() {
        users = tempUsers
          ..sort((a, b) => a['username'].compareTo(b['username']));
        userProgressData = progressData;
      });
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Friends Tracker'),
      ),
      body: users.isEmpty
          ? Center(
              child: Text('No other users found',
                  style: TextStyle(color: customColor1)))
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                String userId = users[index]['userId'];
                String username = users[index]['username'];

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ExpansionTile(
                    tilePadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    title: Text(username,
                        style: TextStyle(
                            color: customColor1, fontWeight: FontWeight.bold)),
                    children: [
                      _buildDailyTracker(userId, DateTime.now()),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Previous Progress',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: customColor2),
                        ),
                      ),
                      _buildCalendar(userId),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDailyTracker(String userId, DateTime date) {
    String dateKey = DateFormat('yyyy-MM-dd').format(date);
    Map<String, bool> tasks = userProgressData[userId]?[dateKey] ??
        {
          'Call': false,
          'Steps': false,
          'Meditation': false,
          'Learning': false,
          'Add Value': false,
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: tasks.keys.map((task) {
          return CheckboxListTile(
            title: Text(task, style: TextStyle(color: customColor3)),
            value: tasks[task],
            onChanged: null,
            activeColor: customColor1,
            checkColor: Colors.white,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendar(String userId) {
    int daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    int firstDayOfWeek = DateTime(selectedYear, selectedMonth, 1).weekday % 7;
    List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      margin: EdgeInsets.all(8),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: customColor3.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildMonthYearSelector(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: customColor2),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 8),
          GridView.builder(
            physics: NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: daysInMonth + firstDayOfWeek,
            itemBuilder: (context, index) {
              if (index < firstDayOfWeek) return Container();
              int day = index - firstDayOfWeek + 1;
              String dateKey =
                  '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

              return InkWell(
                onTap: () => _showDailyTrackerDialog(userId, dateKey),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color:
                        userProgressData[userId]?.containsKey(dateKey) ?? false
                            ? customColor3.withOpacity(0.5)
                            : Colors.white,
                    border: Border.all(color: customColor1),
                  ),
                  child: Text('$day',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: customColor1)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthYearSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_left, color: customColor1),
          onPressed: () {
            setState(() {
              if (selectedMonth == 1) {
                selectedMonth = 12;
                selectedYear--;
              } else {
                selectedMonth--;
              }
            });
          },
        ),
        Text(
            '${DateFormat('MMMM yyyy').format(DateTime(selectedYear, selectedMonth))}',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: customColor1)),
        IconButton(
          icon: Icon(Icons.arrow_right, color: customColor1),
          onPressed: () {
            setState(() {
              if (selectedMonth == 12) {
                selectedMonth = 1;
                selectedYear++;
              } else {
                selectedMonth++;
              }
            });
          },
        ),
      ],
    );
  }

  void _showDailyTrackerDialog(String userId, String dateKey) {
    Map<String, bool> tasks = userProgressData[userId]?[dateKey] ??
        {
          'Call': false,
          'Steps': false,
          'Meditation': false,
          'Learning': false,
          'Add Value': false,
        };

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Daily Tracker", style: TextStyle(color: customColor1)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: tasks.keys.map((task) {
              return CheckboxListTile(
                  title: Text(task, style: TextStyle(color: customColor2)),
                  value: tasks[task],
                  onChanged: null);
            }).toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Close", style: TextStyle(color: customColor1)))
          ],
        );
      },
    );
  }
}
