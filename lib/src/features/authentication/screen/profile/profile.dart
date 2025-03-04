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

// Dummy screens (Replace with your actual screens)
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
        // When back button is pressed, navigate to CurvedNavBar
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

                  // Fetch and Display User Data
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
