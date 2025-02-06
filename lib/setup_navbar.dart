import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/notes_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';

class CurvedNavBar extends StatefulWidget {
  const CurvedNavBar({super.key});

  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> {
  int index = 2;

  final _screens = [
    Meditation(),
    StepTracker(),
    DashboardScreen(),
    Leaderboard(),
    Notes()
  ];

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Icon(Icons.alarm_on_outlined, size: 30),
      Icon(
        Icons.directions_walk,
        size: 30,
      ),
      Icon(
        Icons.home_outlined,
        size: 30,
      ),
      Icon(
        Icons.star_border,
        size: 30,
      ),
      Icon(
        Icons.notes_outlined,
        size: 30,
      )
    ];

    return Scaffold(
      body: _screens[index],
      bottomNavigationBar: CurvedNavigationBar(
        animationDuration: Duration(milliseconds: 300),
        backgroundColor: Colors.transparent,
        buttonBackgroundColor: const Color(0xFFEFD199),
        color: const Color(0xFF80C8BC),
        index: index,
        items: items,
        onTap: (index) => setState(() => this.index = index),
      ),
    );
  }
}
