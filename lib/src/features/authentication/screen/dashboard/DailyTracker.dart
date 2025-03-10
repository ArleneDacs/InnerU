import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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

      // ✅ Debugging: Print user list before setting state
      print("Usernames before setState:");
      tempUsers.forEach((user) => print(user['username']));

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
      appBar: AppBar(title: Text('Friends Tracker')),
      body: users.isEmpty
          ? Center(child: Text('No other users found'))
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                String userId = users[index]['userId'];
                String username = users[index]['username'];

                return ExpansionTile(
                  title: Text(username),
                  children: [
                    _buildDailyTracker(userId, DateTime.now()),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('Previous Progress',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    _buildCalendar(userId),
                  ],
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
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: tasks.keys.map((task) {
          return CheckboxListTile(
            title: Text(task),
            value: tasks[task],
            onChanged: null,
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
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
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
                    style: TextStyle(fontWeight: FontWeight.bold),
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
                            ? Colors.greenAccent
                            : Colors.white,
                    border: Border.all(color: Colors.black),
                  ),
                  child: Text('$day',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
          icon: Icon(Icons.arrow_left),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        IconButton(
          icon: Icon(Icons.arrow_right),
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
          title: Text("Daily Tracker"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: tasks.keys.map((task) {
              return CheckboxListTile(
                  title: Text(task), value: tasks[task], onChanged: null);
            }).toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text("Close"))
          ],
        );
      },
    );
  }
}
