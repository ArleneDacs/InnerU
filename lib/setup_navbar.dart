import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/addcoach.dart';
import 'package:selfcare_projects/src/features/authentication/screen/community/community_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth for user management

class Setuppage extends StatefulWidget {
  const Setuppage({super.key});
  @override
  State<Setuppage> createState() => _SetuppageState();
}

class _SetuppageState extends State<Setuppage> {
  int index = 2;
  User? currentUser; // Variable to hold the current user

  final _screens = [
    Meditation(),
    StepTracker(),
    DashboardScreen(),
    TodoList(),
    CommunityScreen()
  ];

  final _titles = ["Meditation", "Step Tracker", "", "To Do List", "Community"];

  // Default (unselected) icons
  final List<Widget> _defaultIcons = [
    Icon(CupertinoIcons.suit_heart, size: 30),
    Icon(Icons.directions_walk_outlined, size: 30),
    Icon(Icons.dashboard_outlined, size: 30),
    Icon(CupertinoIcons.lightbulb, size: 30),
    Icon(Icons.edit_outlined, size: 30),
  ];

  // Selected (active) icons
  final List<Widget> _selectedIcons = [
    Icon(CupertinoIcons.suit_heart_fill, size: 30),
    Icon(Icons.directions_walk, size: 30),
    Icon(Icons.dashboard, size: 30),
    Icon(CupertinoIcons.lightbulb_fill, size: 30),
    Icon(Icons.edit, size: 30),
  ];

  final String allowedUserId =
      "hG1FxGW2xrVXtKZnnDWERJpPQof2"; // Replace with the actual allowed user ID

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  void _getCurrentUser() {
    currentUser =
        FirebaseAuth.instance.currentUser; // Get the current user from Firebase
    if (currentUser?.uid == allowedUserId) {
      // If user is allowed, add supervisor icon
      _defaultIcons.add(Icon(Icons.supervisor_account, size: 30));
      _selectedIcons.add(Icon(Icons.supervisor_account, size: 30));
    }
    setState(() {}); // Update UI after fetching user
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: index == 2
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_titles[index]),
              ),
              actions: [
                IconButton(
                  icon: Icon(CupertinoIcons.line_horizontal_3, size: 28),
                  onPressed: () {
                    BottomSheetWidget.show(context);
                  },
                ),
              ],
            ),
      body: _screens[index],
      bottomNavigationBar: CurvedNavigationBar(
        height: 60,
        animationDuration: Duration(milliseconds: 300),
        backgroundColor: Colors.transparent,
        buttonBackgroundColor: const Color(0xFFEFD199),
        color: const Color(0xFF90A17D),
        index: index,
        items: List.generate(_defaultIcons.length,
            (i) => i == index ? _selectedIcons[i] : _defaultIcons[i]),
        onTap: (newIndex) {
          // Check if the Supervisor icon is clicked
          if (newIndex == _defaultIcons.length - 1 &&
              currentUser?.uid == allowedUserId) {
            // Navigate to AddCoach page if the Supervisor icon is clicked
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      AddCoachScreen()), // Replace with actual AddCoach screen
            );
          } else {
            setState(
                () => index = newIndex); // Normal navigation for other icons
          }
        },
      ),
    );
  }
}
