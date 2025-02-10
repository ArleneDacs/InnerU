import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/edit_profile/edit_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';

// Dummy screens (Replace with your actual screens)
class EditProfileScreen extends StatelessWidget {
  
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text("Edit Profile")));
}

class ChangeMeditationScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text("Change Meditation Song")));
}

class PrivacyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text("Privacy")));
}

class SubscriptionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text("Manage Subscription")));
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
  // Logout confirmation dialog
  Future<void> _showLogOutDialog(BuildContext context) async {
    setState(() => _isPressed = true);
    await Future.delayed(Duration(milliseconds: 300));
    setState(() => _isPressed = false);

    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Log out'),
        content: Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
            },
            child: Text('Yes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double containerWidth = screenWidth * 0.85;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                          base64Decode(_base64Image!), // Decode the base64 string to display the image
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
                          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "$email",
                          style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                

                SizedBox(height: 20),

                // Section Titles & Buttons with Navigation
                _buildSectionTitle("General"),
                _buildButton(context, "Edit Profile", EditProfile(title: 'Edit Profile',)),

                _buildSectionTitle("Audio Settings"),
                _buildButton(context, "Change Meditation Song", ChangeMeditationScreen()),

                _buildSectionTitle("Account Settings"),
                _buildButton(context, "Privacy", PrivacyScreen()),

                _buildSectionTitle("Subscription"),
                _buildButton(context, "Manage Subscription", SubscriptionScreen()),

                SizedBox(height: 10),

                // Logout Button
                ElevatedButton(
                  onPressed: () => _showLogOutDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPressed ? Color(0xFFCE8F5A) : Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Color(0xFFCE8F5A), width: 2),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 50, vertical: 10),
                  ),
                  child: Text(
                    'Log-out',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isPressed ? Colors.white : Color(0xFFCE8F5A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Section Title Widget
  Widget _buildSectionTitle(String title) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: EdgeInsets.only(top: 10, bottom: 10),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(color: Color(0xFFc4f0d9), borderRadius: BorderRadius.circular(5)),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  // Button Widget with Navigation
  Widget _buildButton(BuildContext context, String label, Widget targetScreen) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => targetScreen)),
        style: ButtonStyle(
          padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
          overlayColor: MaterialStateProperty.all(Colors.grey.shade200),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 17, color: Colors.black)),
            Icon(Icons.arrow_forward_ios, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
