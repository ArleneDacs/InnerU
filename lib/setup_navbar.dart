import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/community/community_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth for user management

class Setuppage extends StatefulWidget {
  const Setuppage({super.key});
  @override
  State<Setuppage> createState() => _SetuppageState();
}

class _SetuppageState extends State<Setuppage> {
  int index = 2;

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
          setState(() => index = newIndex); // Normal navigation for other icons
        },
      ),
    );
  }
}
