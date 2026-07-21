import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/addcoach.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/session_cleanup_service.dart';

class BottomSheetWidget {
  static void show(BuildContext context) async {
    final currentUser = AuthService.instance.currentSession;
    String allowedUserId =
        "hG1FxGW2xrVXtKZnnDWERJpPQof2"; // Replace with actual allowed user ID

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
                  leading: Icon(Icons.settings),
                  title: Text("Account Settings"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PrivacyScreen(title: 'Privacy'),
                      ),
                    );
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

                // Conditionally show "Add Coach" icon only for specific user
                if (currentUser?.id.toString() == allowedUserId) ...[
                  ListTile(
                    leading: Icon(Icons.supervisor_account),
                    title: Text("Add Coach"),
                    onTap: () {
                      Navigator.pop(
                          context); // Close the current drawer or menu
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AddCoachScreen(), // Navigate to AddCoachScreen
                        ),
                      );
                    },
                  ),
                  Divider(),
                ],

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
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await SessionCleanupService.signOut();
              if (!navigator.mounted) return;

              // Close the dialog
              navigator.pop();

              // Navigate to LoginScreen and remove all previous routes
              navigator.pushAndRemoveUntil(
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
