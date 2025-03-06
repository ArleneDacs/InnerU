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
import 'package:cloud_firestore/cloud_firestore.dart';

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
  bool isLoading = true;
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
    UserService.getUserData().then((data) {
      setState(() {
        username = data["username"]!;
        email = data["email"]!;
        _base64Image = data["profilePic"];
      });
    });

    fetchDailyTrackerData(); // Fetch Firestore data
  }

  void fetchDailyTrackerData() async {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // Fetch the username based on userId
      DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users') // Assuming 'users' collection stores user data
          .doc(userId)
          .get();

      if (userSnapshot.exists) {
        String username =
            (userSnapshot.data() as Map<String, dynamic>)['username'];
        String documentId =
            '$username-$todayDate'; // Use username instead of userId

        DocumentSnapshot snapshot = await FirebaseFirestore.instance
            .collection('dailytracker')
            .doc(documentId)
            .get();

        if (snapshot.exists) {
          Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
          String lastUpdated = data['lastUpdated'] ?? "";

          // If last updated date is different from today, reset tasks
          if (lastUpdated != todayDate) {
            resetDailyTracker(todayDate, username);
          } else {
            setState(() {
              todayTasks['Meditation'] = data['meditation'] ?? false;
              todayTasks['Steps'] = data['steps'] ?? false;
              todayTasks['Call'] = data['call'] ?? false;
              todayTasks['Learning'] = data['learning'] ?? false;
              todayTasks['Add Value'] = data['addValue'] ?? false;
              isLoading = false;
            });
          }
        } else {
          resetDailyTracker(
              todayDate, username); // If no data exists, create a fresh tracker
        }
      } else {
        print("Error: User document does not exist.");
      }
    } catch (e) {
      print("Error fetching Firestore data: $e");
      setState(() => isLoading = false);
    }
  }

  void resetDailyTracker(String todayDate, String username) async {
    String documentId = '$username-$todayDate';

    // Reset task values
    setState(() {
      todayTasks = {
        'Call': false,
        'Steps': false,
        'Meditation': false,
        'Learning': false,
        'Add Value': false,
      };
      isLoading = false;
    });

    // Save the reset tracker to Firestore
    await FirebaseFirestore.instance
        .collection('dailytracker')
        .doc(documentId)
        .set({
      'meditation': false,
      'steps': false,
      'call': false,
      'learning': false,
      'addValue': false,
      'lastUpdated': todayDate, // Store last updated date
    });
  }

  Future<Set<int>> _fetchTrackedDays() async {
    String userId = FirebaseAuth.instance.currentUser!.uid;

    // Fetch the username based on userId
    DocumentSnapshot userSnapshot =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

    if (!userSnapshot.exists) {
      print("Error: User document does not exist.");
      return {};
    }

    String username = (userSnapshot.data() as Map<String, dynamic>)['username'];
    String monthPrefix =
        '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}';

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('dailytracker')
          .where(FieldPath.documentId,
              isGreaterThanOrEqualTo: "$username-$monthPrefix-01")
          .where(FieldPath.documentId,
              isLessThanOrEqualTo: "$username-$monthPrefix-31")
          .get();

      Set<int> trackedDays = snapshot.docs
          .map((doc) {
            String datePart = doc.id.split('-').last;
            return int.tryParse(datePart) ?? 0;
          })
          .where((day) => day > 0)
          .toSet();

      return trackedDays;
    } catch (e) {
      print("Error fetching tracked days: $e");
      return {};
    }
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
            value: taskMap[task] ?? false,
            onChanged: null, // Keep this as null to disable interaction
          ),
          InkWell(
            onTap: () {
              // Handle the task click here
              print('Tapped on $task');
            },
            child: Text(
              task,
              style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0)),
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

    return FutureBuilder<Set<int>>(
      future: _fetchTrackedDays(), // Fetch tracked days
      builder: (context, snapshot) {
        Set<int> trackedDays = snapshot.data ?? {};

        return Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          constraints: BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                spreadRadius: 2,
                offset: Offset(4, 4),
              ),
            ],
          ),
          child: Column(
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
                    return Container();
                  }
                  int day = index - firstDayOfWeek + 1;

                  DateTime currentDate = DateTime.now();
                  bool isPastDay = DateTime(selectedYear, selectedMonth, day)
                      .isBefore(DateTime(currentDate.year, currentDate.month,
                          currentDate.day));

                  bool hasData =
                      trackedDays.contains(day); // Check if day has data

                  return InkWell(
                    onTap: () => _showDailyTrackerDialog(day),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: (day == currentDate.day &&
                                selectedMonth == currentDate.month &&
                                selectedYear == currentDate.year)
                            ? Colors.greenAccent // Today's highlight
                            : (isPastDay && hasData
                                ? Colors
                                    .greenAccent // Highlight past days with data
                                : Colors.white), // Default for other days
                        border: Border.all(color: Colors.black),
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black, // Always keep text black
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

// Popup for Previous Days
  void _showDailyTrackerDialog(int day) async {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    String selectedDate = DateFormat('yyyy-MM-dd')
        .format(DateTime(selectedYear, selectedMonth, day));

    // Fetch the username based on userId
    DocumentSnapshot userSnapshot =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

    if (userSnapshot.exists) {
      String username =
          (userSnapshot.data() as Map<String, dynamic>)['username'];
      String documentId = '$username-$selectedDate';

      // Fetch the daily tracker data for the selected date from Firestore
      Map<String, bool> selectedDateTasks = {
        'Call': false,
        'Steps': false,
        'Meditation': false,
        'Learning': false,
        'Add Value': false,
      };

      try {
        DocumentSnapshot snapshot = await FirebaseFirestore.instance
            .collection('dailytracker')
            .doc(documentId)
            .get();

        if (snapshot.exists) {
          Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
          selectedDateTasks = {
            'Call': data['call'] ?? false,
            'Steps': data['steps'] ?? false,
            'Meditation': data['meditation'] ?? false,
            'Learning': data['learning'] ?? false,
            'Add Value': data['addValue'] ?? false,
          };
        } else {
          print("No data found for $selectedDate.");
        }
      } catch (e) {
        print("Error fetching Firestore data for $selectedDate: $e");
      }

      // Show the dialog with fetched data
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Tracker for $selectedMonth/$day/$selectedYear"),
            content: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: selectedDateTasks.keys.map((task) {
                    return CheckboxListTile(
                      title: Text(task),
                      value: selectedDateTasks[task],
                      onChanged:
                          null, // Checkboxes are not interactive in this dialog
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
    } else {
      print("Error: User document does not exist.");
    }
  }
}
