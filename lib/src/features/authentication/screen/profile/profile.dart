import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/edit_profile/edit_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/models/community_bottom_sheet.dart';
import 'package:intl/intl.dart';

class EditProfileScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Edit Profile")));
}

class ChangeMeditationScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Change Meditation Song")));
}

class SubscriptionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text("Manage Subscription")));
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.title});
  final String title;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isPressed = false;
  String username = "Loading...";
  String email = "Loading...";
  String? _base64Image;

  // Daily Tracker related variables
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  Map<String, Map<String, bool>> dailyTasks = {}; // Simulated database storage
  Map<String, bool> todayTasks = {
    'Call': false,
    'Steps': false,
    'Meditation': false,
    'Learning': false,
    'Add Value': false,
  };

  @override
  void initState() {
    super.initState();
    UserService.getUserData().then((data) => setState(() {
          username = data["username"]!;
          email = data["email"]!;
          _base64Image = data["profilePic"];
        }));
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double containerWidth = screenWidth * 0.85;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  Setuppage()), // Replace with your actual CurvedNavBar widget
          (route) => false, // Removes all previous routes from the stack
        );
        return false; // Prevent the default back navigation
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
                onPressed: () => CommunityBottomSheet.show(context),
                icon: Icon(Icons.edit))
          ],
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                children: [
                  _base64Image == null
                      ? Image.asset(
                          'assets/images/avatar.png', // Default image if no profilePic is available
                          width: screenWidth * 0.35,
                          height: screenWidth * 0.35,
                        )
                      : ClipOval(
                          child: Image.memory(
                            base64Decode(
                                _base64Image!), // Decode the base64 string to display the image
                            width: screenWidth * 0.35,
                            height: screenWidth * 0.35,
                            fit: BoxFit.cover,
                          ),
                        ),
                  SizedBox(height: 10),
                  Column(
                    children: [
                      Text(
                        "$username",
                        style: TextStyle(
                            fontSize: 25, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "$email",
                        style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // Start of Daily Tracker Section
                  Text(
                    'Daily Tracker',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  _buildTaskRow('Call', todayTasks),
                  _buildTaskRow('Steps', todayTasks),
                  _buildTaskRow('Meditation', todayTasks),
                  _buildTaskRow('Learning', todayTasks),
                  _buildTaskRow('Add Value', todayTasks),

                  SizedBox(height: 16),

                  ExpansionTile(
                    title: Text(
                      'View Previous Progress',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    children: [_buildCalendar()],
                  ),
                  // End of Daily Tracker Section
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Builds each task row for Today's tracker
  Widget _buildTaskRow(String task, Map<String, bool> taskMap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Checkbox(
            value: taskMap[task],
            onChanged: (newValue) {
              setState(() {
                taskMap[task] = newValue!;
              });
            },
          ),
          Text(task),
          Spacer(),
          SizedBox(
            width: 150,
            height: 40,
            child: ElevatedButton(
              onPressed: () {},
              child: Center(child: Text(task)),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the Calendar for Previous Days
  Widget _buildCalendar() {
    int daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
    int firstDayOfWeek = DateTime(selectedYear, selectedMonth, 1).weekday % 7;
    List<String> weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DropdownButton<int>(
              value: selectedMonth,
              onChanged: (newMonth) {
                setState(() {
                  selectedMonth = newMonth!;
                });
              },
              items: List.generate(
                12,
                (index) => DropdownMenuItem<int>(
                  value: index + 1,
                  child: Text(DateFormat('MMMM')
                      .format(DateTime(selectedYear, index + 1, 1))),
                ),
              ),
            ),
            SizedBox(width: 16),
            DropdownButton<int>(
              value: selectedYear,
              onChanged: (newYear) {
                setState(() {
                  selectedYear = newYear!;
                });
              },
              items: List.generate(
                10,
                (index) => DropdownMenuItem<int>(
                  value: DateTime.now().year - 5 + index,
                  child: Text('${DateTime.now().year - 5 + index}'),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: weekdays
              .map((day) => Expanded(
                    child: Center(
                      child: Text(day,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ))
              .toList(),
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
            if (index < firstDayOfWeek) {
              return Container(); // Empty spaces before first day
            }
            int day = index - firstDayOfWeek + 1;
            return InkWell(
              onTap: () => _showDailyTrackerDialog(day),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: (day == DateTime.now().day &&
                          selectedMonth == DateTime.now().month)
                      ? Colors.green
                      : Colors.white,
                  border: Border.all(color: Colors.black),
                ),
                child:
                    Text('$day', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ],
    );
  }

  // Popup for Previous Days
  void _showDailyTrackerDialog(int day) {
    String dateKey = '$selectedYear-$selectedMonth-$day';
    dailyTasks.putIfAbsent(
        dateKey,
        () => {
              'Call': false,
              'Steps': false,
              'Meditation': false,
              'Learning': false,
              'Add Value': false,
            });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Previous Tracker - $selectedMonth/$day/$selectedYear"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: dailyTasks[dateKey]!.keys.map((task) {
                  return CheckboxListTile(
                    title: Text(task),
                    value: dailyTasks[dateKey]![task],
                    onChanged: (bool? value) {
                      setState(() {
                        dailyTasks[dateKey]![task] = value!;
                      });
                    },
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close"),
            ),
          ],
        );
      },
    );
  }
}
