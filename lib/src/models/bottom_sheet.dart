import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';

class BottomSheetWidget {
  static void show(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Color(0xFF589675),
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ListTileTheme(
          iconColor: Colors.white,
          textColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.person),
                  title: Text("Profile"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/profile');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.face),
                  title: Text("Mood Tracker"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/emotionScreen');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(
                    Icons.star,
                    color: const Color(0xFFF3DDB3),
                  ),
                  title: Text("Leaderboard"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/leaderboard');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(CupertinoIcons.rosette),
                  title: Text("Coaches"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/coachesScreen');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Image.asset(
                    "assets/images/logout.png",
                    height: 25,
                  ),
                  title: Text("Log out"),
                  onTap: () {
                    _showLogOutDialog(context); // Show log out dialog
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Log out dialog
  static Future<void> _showLogOutDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Sign out the user from Firebase
              await FirebaseAuth.instance.signOut();

              // Close the dialog
              Navigator.pop(context);

              // Navigate to LoginScreen and remove all previous routes
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
                (route) => false, // Removes all previous routes from the stack
              );
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }
}
