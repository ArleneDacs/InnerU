import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart'; // <-- Added shimmer package

// Custom Colors
const customColor1 = Color(0xFF6D849A); // Primary color
const customColor2 = Color(0xFFCE8F5A); // Secondary color
const customColor3 = Color(0xFF90A17D); // Accent color

class UserProgressPage extends StatefulWidget {
  const UserProgressPage({super.key});

  @override
  _UserProgressPageState createState() => _UserProgressPageState();
}

class _UserProgressPageState extends State<UserProgressPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> users = [];
  Map<String, Map<String, Map<String, bool>>> userProgressData = {};
  final Map<String, String> _usernameCache = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _trackerSubscription;
  String currentUserId = '';
  String currentUserName = '';
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  bool isLoading = true; // <-- Added loading flag

  @override
  void initState() {
    super.initState();
    fetchCurrentUserId();
  }

  Future<void> fetchCurrentUserId() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final currentUsername =
          _normalizedUsername(userDoc.data()?['username']) ?? '';

      if (!mounted) return;

      setState(() {
        currentUserId = user.uid;
        currentUserName = currentUsername;
      });

      fetchUsersAndProgress();
    }
  }

  void fetchUsersAndProgress() {
    _trackerSubscription?.cancel();
    _trackerSubscription =
        _firestore.collection('dailytracker').snapshots().listen(
      (trackerSnapshot) async {
        Set<String> uniqueUserIds = {};
        Map<String, Map<String, Map<String, bool>>> progressData = {};
        Map<String, String> userIdToUsername = {};
        List<Map<String, dynamic>> tempUsers = [];

        for (var doc in trackerSnapshot.docs) {
          final userData = doc.data();
          final userId = (userData['userId'] as String?)?.trim();

          if (userId == null || userId.isEmpty || userId == currentUserId) {
            continue;
          }

          final trackerUsername = _normalizedUsername(userData['username']);
          if (trackerUsername != null) {
            userIdToUsername[userId] = trackerUsername;
            _usernameCache[userId] = trackerUsername;
          }

          uniqueUserIds.add(userId);

          final trackerDate = _resolveTrackerDate(userData);
          progressData.putIfAbsent(userId, () => {});
          progressData[userId]![trackerDate] = {
            'Call': userData['call'] ?? false,
            'Steps': userData['steps'] ?? false,
            'Exercise': userData['exercise'] ?? false,
            'Meditation': userData['meditation'] ?? false,
            'Learning': userData['learning'] ?? false,
            'Add Value': userData['addValue'] ?? false,
          };
        }

        final resolvedUsernames =
            await _resolveUsernames(uniqueUserIds, userIdToUsername);

        for (var userId in uniqueUserIds) {
          tempUsers.add({
            'userId': userId,
            'username': resolvedUsernames[userId] ?? 'Unknown',
          });
        }

        if (!mounted) return;

        setState(() {
          users = tempUsers
            ..sort((a, b) => (a['username'] as String)
                .toLowerCase()
                .compareTo((b['username'] as String).toLowerCase()));
          userProgressData = progressData;
          isLoading = false;
        });
      },
    );
  }

  String? _normalizedUsername(dynamic value) {
    if (value is! String) return null;

    final username = value.trim();
    if (username.isEmpty ||
        username == 'Unknown' ||
        username == 'Unknown User') {
      return null;
    }

    return username;
  }

  String _resolveTrackerDate(Map<String, dynamic> userData) {
    final rawDate = userData['lastUpdated'] ?? userData['date'];
    final trackerDate = rawDate is String ? rawDate.trim() : '';

    if (trackerDate.isNotEmpty) {
      return trackerDate;
    }

    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  Future<Map<String, String>> _resolveUsernames(
    Set<String> userIds,
    Map<String, String> trackerUsernames,
  ) async {
    final resolvedUsernames = <String, String>{...trackerUsernames};
    final missingUserIds = <String>[];

    for (final userId in userIds) {
      final cachedUsername = _usernameCache[userId];
      if (cachedUsername != null && cachedUsername.isNotEmpty) {
        resolvedUsernames[userId] = cachedUsername;
        continue;
      }

      if (!resolvedUsernames.containsKey(userId)) {
        missingUserIds.add(userId);
      }
    }

    if (missingUserIds.isEmpty) {
      return resolvedUsernames;
    }

    final userDocs = await Future.wait(
      missingUserIds
          .map((userId) => _firestore.collection('users').doc(userId).get()),
    );

    for (final userDoc in userDocs) {
      final username = _normalizedUsername(userDoc.data()?['username']);
      if (username == null) continue;

      _usernameCache[userDoc.id] = username;
      resolvedUsernames[userDoc.id] = username;
    }

    return resolvedUsernames;
  }

  @override
  void dispose() {
    _trackerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Friends Tracker'),
      ),
      body: isLoading
          ? _buildShimmerLoader()
          : users.isEmpty
              ? Center(
                  child: Text('No other users found',
                      style: TextStyle(color: customColor1)))
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    String userId = users[index]['userId'];
                    String username = users[index]['username'];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        tilePadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Text(username,
                            style: TextStyle(
                                color: customColor1,
                                fontWeight: FontWeight.bold)),
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

  Widget _buildShimmerLoader() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Container(
              height: 100,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 20, width: 150, color: Colors.white),
                  const SizedBox(height: 10),
                  Container(
                      height: 14, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 10),
                  Container(
                      height: 14, width: double.infinity, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDailyTracker(String userId, DateTime date) {
    String dateKey = DateFormat('yyyy-MM-dd').format(date);
    Map<String, bool> tasks = userProgressData[userId]?[dateKey] ??
        {
          'Call': false,
          'Steps': false,
          'Exercise': false,
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
            DateFormat('MMMM yyyy')
                .format(DateTime(selectedYear, selectedMonth)),
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
          'Exercise': false,
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
