import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.title});
  final String title;

  @override
  State<ProfilePage> createState() => _MyprofileState();
}

class _MyprofileState extends State<ProfilePage> {
  Future<Map<String, String>> _getUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {"username": "Guest", "email": "No Email Found"};
    }

    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection("users").doc(user.uid).get();

    if (userDoc.exists) {
      return {
        "username": userDoc["username"] ?? "Unknown",
        "email": userDoc["email"] ?? "No Email Found",
      };
    } else {
      return {"username": "Unknown", "email": "No Email Found"};
    }
  }

  bool _isPressed = false;

  Future<void> _showLogOutDialog(BuildContext context) async {
    setState(() {
      _isPressed = true;
    });

    await Future.delayed(Duration(milliseconds: 500));

    setState(() {
      _isPressed = false;
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Log out'),
          content: Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LoginScreen(),
                  ),
                );
              },
              child: Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double containerWidth = screenWidth * 0.85;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/avatar.png',
                  width: screenWidth * 0.35,
                  height: screenWidth * 0.35,
                ),
                SizedBox(height: 10),
                FutureBuilder<Map<String, String>>(
                  future: _getUserData(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator();
                    } else if (snapshot.hasError) {
                      return Text("Error fetching user data", style: TextStyle(color: Colors.red));
                    } else {
                      return Column(
                        children: [
                          Text(
                            snapshot.data?["username"] ?? "Guest",
                            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            snapshot.data?["email"] ?? "No Email Found",
                            style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                          ),
                        ],
                      );
                    }
                  },
                ),
                SizedBox(height: 50),
                _buildSectionTitle("General", containerWidth),
                _buildButton(context, "Edit Profile", containerWidth),
                _buildSectionTitle("Audio Settings", containerWidth),
                _buildButton(context, "Change Meditation Song", containerWidth),
                _buildSectionTitle("Account Settings", containerWidth),
                _buildButton(context, "Privacy", containerWidth),
                _buildSectionTitle("Subscription", containerWidth),
                _buildButton(context, "Manage Subscription", containerWidth),
                SizedBox(height: 30),
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

  Widget _buildSectionTitle(String title, double width) {
    return Container(
      alignment: Alignment.centerLeft,
      width: 700,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(color: Color(0xFFc4f0d9)),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildButton(BuildContext context, String label, double width) {
    return Container(
      margin: EdgeInsets.only(top: 5),
      width: width,
      child: TextButton(
        onPressed: () {},
        style: ButtonStyle(padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 15, horizontal: 20))),
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