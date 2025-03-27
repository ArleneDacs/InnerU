import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/setup_navbar.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/edit_profile/edit_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_type.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';
import 'package:selfcare_projects/src/models/community_bottom_sheet.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

const customColor1 = Color(0xFF6D849A); // Example primary color
const customColor2 = Color(0xFFCE8F5A); // Example secondary color
const customColor3 = Color(0xFF90A17D); // Example accent color

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
  String selectedCategory = '';
  bool isLoading = true;
  String username = "Loading...";
  String email = "Loading...";
  String? _profilePicUrl;

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
      });
    });
    _fetchProfilePic();
    fetchDailyTrackerData(); // Fetch Firestore data
    listenToDailyTrackerUpdates(); // Start listening to database changes
  }

  void listenToDailyTrackerUpdates() {
    String userId = FirebaseAuth.instance.currentUser!.uid;
    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get()
        .then((userSnapshot) {
      if (userSnapshot.exists) {
        String username =
            (userSnapshot.data() as Map<String, dynamic>)['username'];
        String documentId = '$username-$todayDate';

        FirebaseFirestore.instance
            .collection('dailytracker')
            .doc(documentId)
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists) {
            fetchDailyTrackerData(); // Fetch data whenever there's a change
          }
        });
      }
    });
  }

  Future<void> _fetchProfilePic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          _profilePicUrl = userDoc["profilePic"]; // URL from Firestore
        });
      }
    } catch (e) {
      print("Error fetching profile picture: $e");
    }
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
          checkAndAssignPoints();
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

  void checkAndAssignPoints() async {
  String userId = FirebaseAuth.instance.currentUser!.uid;
  String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  try {
    DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (userSnapshot.exists) {
      Map<String, dynamic> userData = userSnapshot.data() as Map<String, dynamic>;
      String username = userData['username'];
      String server = userData['team'] ?? "Default"; // Get user's team
      String documentId = '$username-$todayDate';

      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('dailytracker')
          .doc(documentId)
          .get();

      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

        // Get actual activity counts from dailytracker (if available)
        int meditationMinutes = data['meditationMinutes'] ?? 0;
        int stepsTaken = data['stepCount'] ?? 0;
        int callsMade = data['callCount'] ?? 0;
        int learningEntries = data['learningCount'] ?? 0;
        int valueEntries = data['valueCount'] ?? 0;

        // Define tasks and points for individual tasks
        Map<String, bool> taskCompletion = {
          'Meditation': data['meditation'] ?? false,
          'Steps': data['steps'] ?? false,
          'Call': data['call'] ?? false,
          'Learning': data['learning'] ?? false,
          'Add Value': data['addValue'] ?? false,
        };

        // Calculate points based on actual activity
        Map<String, int> taskPoints = {
          'Meditation Points': meditationMinutes, // 1 point per minute
          'Steps Points': (stepsTaken / 200).floor(), // 1 point per 200 steps
          'Call Points': callsMade, // 1 point per call
          'Learning Points': learningEntries, // 1 point per entry
          'Add Value Points': valueEntries, // 1 point per entry
        };

        // Fallback to fixed points if activity counts are not available
        if (meditationMinutes == 0 && taskCompletion['Meditation'] == true) {
          taskPoints['Meditation Points'] = 5;
        }
        if (stepsTaken == 0 && taskCompletion['Steps'] == true) {
          taskPoints['Steps Points'] = 10;
        }
        if (callsMade == 0 && taskCompletion['Call'] == true) {
          taskPoints['Call Points'] = 10;
        }
        if (learningEntries == 0 && taskCompletion['Learning'] == true) {
          taskPoints['Learning Points'] = 15;
        }
        if (valueEntries == 0 && taskCompletion['Add Value'] == true) {
          taskPoints['Add Value Points'] = 15;
        }

        int totalPoints = taskPoints.values.reduce((a, b) => a + b);

        // Save points in the userpoints collection
        await FirebaseFirestore.instance
            .collection('userpoints')
            .doc(documentId)
            .set({
          'username': username,
          'date': todayDate,
          'totalPoints': totalPoints,
          'taskPoints': taskPoints,
          'tasks': taskCompletion,
          'server': server,
          // Store raw activity counts for better display
          'activityCounts': {
            'meditationMinutes': meditationMinutes,
            'stepsTaken': stepsTaken,
            'callsMade': callsMade,
            'learningEntries': learningEntries,
            'valueEntries': valueEntries,
          }
        });

        print("Total points assigned: $totalPoints");
        print("Points per task: $taskPoints");
      } else {
        print("No daily tracker data found for today.");
      }
    } else {
      print("Error: User document does not exist.");
    }
  } catch (e) {
    print("Error in assigning points: $e");
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
                  _profilePicUrl == null
                      ? Image.asset(
                          'assets/images/avatar.png', // Default image if no profilePic is available
                          width: screenWidth * 0.35,
                          height: screenWidth * 0.35,
                        )
                      : ClipOval(
                          child: Image.network(
                            _profilePicUrl!,
                            width: screenWidth * 0.35,
                            height: screenWidth * 0.35,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return SizedBox(
                                width: screenWidth * 0.35,
                                height: screenWidth * 0.35,
                                child:
                                    CircularProgressIndicator(), // Loading indicator
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Image.asset(
                                'assets/images/avatar.png', // Fallback image on error
                                width: screenWidth * 0.35,
                                height: screenWidth * 0.35,
                              );
                            },
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
    bool isCompleted = taskMap[task] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Checkbox(
            value: isCompleted,
            activeColor: customColor1, // Applied customColor1 here
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onChanged: null, // Checkbox is no longer tappable
          ),
          InkWell(
            onTap: () {
              print('Tapped on $task');
            },
            child: Text(
              task,
              style: TextStyle(
                color: isCompleted
                    ? customColor3
                    : Colors.black, // Applied customColor3 for completed tasks
                fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
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
      future: _fetchTrackedDays(),
      builder: (context, snapshot) {
        Set<int> trackedDays = snapshot.data ?? {};

        return Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(16),
          constraints: BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
                color: customColor2,
                width: 2), // Applied customColor2 for the calendar border
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
                        child: Text(
                          DateFormat('MMMM')
                              .format(DateTime(selectedYear, index + 1, 1)),
                        ),
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
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        customColor1)), // Applied customColor1 for weekday labels
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

                  bool hasData = trackedDays.contains(day);

                  return InkWell(
                    onTap: () => _showDailyTrackerDialog(day),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: (day == currentDate.day &&
                                selectedMonth == currentDate.month &&
                                selectedYear == currentDate.year)
                            ? customColor2 // Applied customColor2 to highlight today's date
                            : (isPastDay && hasData
                                ? customColor3 // Applied customColor3 to highlight past days with data
                                : Colors.white), // Default for other days
                        border: Border.all(
                            color:
                                customColor1), // Applied customColor1 for calendar day borders
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color.fromARGB(255, 0, 0,
                              0), // Applied customColor1 for day numbers
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
