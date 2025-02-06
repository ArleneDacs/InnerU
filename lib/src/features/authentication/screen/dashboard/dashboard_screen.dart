import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';

class DashboardScreen extends StatelessWidget {
  Future<String> _getUsername() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return "User";

    DocumentSnapshot userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      return userDoc["username"] ?? "User";
    } else {
      return "User";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFE0F2F1),
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.person, size: 28, color: Colors.black),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.line_horizontal_3,
                size: 28, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfilePage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: _getUsername(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text("Loading...",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
                } else if (snapshot.hasError) {
                  return Text("Error loading username",
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
                }
                return Text("Hello, ${snapshot.data}!",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
              },
            ),
            SizedBox(height: 10),
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.start, // Aligns items to the top-left
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Aligns text to the left
                children: [
                  Text(
                    "Quotes of the Day",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                ],
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoCard("Steps", "2k", CupertinoIcons.flame_fill,
                    Colors.brown.shade300),
                _buildInfoCard("Meditation", "40%", CupertinoIcons.zzz,
                    Colors.green.shade400),
              ],
            ),
            SizedBox(height: 20),
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Coaches",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                ],
              ),
            ),
            SizedBox(height: 20),
            Text("How do you feel today?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text("😀", style: TextStyle(fontSize: 36)),
                Text("😐", style: TextStyle(fontSize: 36)),
                Text("😔", style: TextStyle(fontSize: 36)),
                Text("😡", style: TextStyle(fontSize: 36)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String data, IconData icon, Color color) {
    return Container(
      width: 150,
      height: 100,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white),
                SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 10),
            Text(data,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardRow(String name, String score) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(score, style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
