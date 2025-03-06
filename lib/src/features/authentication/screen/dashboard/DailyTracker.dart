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

      Map<String, Map<String, Map<String, bool>>> progressData = {};
      Map<String, String> usersData = {};

      trackerSnapshot.docs.forEach((doc) {
        String docId = doc.id;
        String userId = docId.split('-')[0];

        if (userId != currentUserId) {
          Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
          String lastUpdated = userData['lastUpdated'];

          if (!usersData.containsKey(userId)) {
            usersData[userId] = userData['username'];
          }

          progressData.putIfAbsent(userId, () => {});
          progressData[userId]![lastUpdated] = {
            'Call': userData['call'] ?? false,
            'Steps': userData['steps'] ?? false,
            'Meditation': userData['meditation'] ?? false,
            'Learning': userData['learning'] ?? false,
            'Add Value': userData['addValue'] ?? false,
          };
        }
      });

      setState(() {
        users = usersData.entries
            .map((entry) => {'userId': entry.key, 'username': entry.value})
            .toList();
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
                  title: Text(username ?? userId),
                  children: [
                    if (userProgressData.containsKey(userId))
                      _buildUserTracker(userId)
                    else
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text("No progress data available"),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildUserTracker(String userId) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Current Day Tracker',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        _buildDailyTracker(userId, DateTime.now()),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Previous Progress',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        _buildMonthYearSelector(),
        _buildCalendar(userId),
      ],
    );
  }

  Widget _buildMonthYearSelector() {
    List<String> months = List.generate(12, (index) {
      return DateFormat.MMMM().format(DateTime(0, index + 1));
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DropdownButton<int>(
          value: selectedMonth,
          onChanged: (newMonth) {
            setState(() {
              selectedMonth = newMonth!;
            });
          },
          items: List.generate(12, (index) {
            return DropdownMenuItem<int>(
              value: index + 1,
              child: Text(months[index]),
            );
          }),
        ),
        SizedBox(width: 20),
        DropdownButton<int>(
          value: selectedYear,
          onChanged: (newYear) {
            setState(() {
              selectedYear = newYear!;
            });
          },
          items: List.generate(10, (index) {
            int year = DateTime.now().year - index;
            return DropdownMenuItem<int>(
              value: year,
              child: Text(year.toString()),
            );
          }),
        ),
      ],
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

          // Calendar grid
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
              if (index < firstDayOfWeek) {
                return Container();
              }
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
          title: Text("Daily Tracker - $dateKey"),
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
