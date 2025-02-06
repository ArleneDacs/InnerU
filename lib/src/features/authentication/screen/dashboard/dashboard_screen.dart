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

    return userDoc.exists ? userDoc["username"] ?? "User" : "User";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFE0F2F1),
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.person, size: 28, color: Colors.black),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ProfilePage()),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.line_horizontal_3,
                size: 28, color: Colors.black),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String>(
              future: _getUsername(),
              builder: (context, snapshot) {
                return Text(
                  snapshot.connectionState == ConnectionState.waiting
                      ? "Loading..."
                      : "Hello, ${snapshot.data}!",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                );
              },
            ),
            SizedBox(height: 20),
            _buildSectionTitle("Quote of the Day"),
            _buildCardContainer(
                height: 100, content: "Your daily inspiration..."),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoCard("Steps", "2k", CupertinoIcons.flame_fill,
                    Colors.brown.shade300),
                _buildInfoCard("Meditation", "40%", CupertinoIcons.hourglass,
                    Colors.green.shade400),
              ],
            ),
            SizedBox(height: 20),
            _buildSectionTitle("Today's Coach"),
            _buildCardContainer(
                height: 120,
                content: "Maychell Alcorin\nCEO of Valentin, Life Coach"),
            SizedBox(height: 20),
            _buildSectionTitle("How do you feel today?"),
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
            SizedBox(height: 20),
            _buildSleepTrackingUI(),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTrackingUI() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text("Sleep Tracking",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SizedBox(height: 10),
          Text("Set your bedtime and sleep goal, then let us do the rest!"),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDropdown("Alarm"),
              _buildDropdown("10:00 PM"),
              _buildDropdown("9 Hrs"),
            ],
          ),
          SizedBox(height: 10),
          Center(
            child: ElevatedButton(
              onPressed: () {},
              child: Text("Save details"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
            ),
          ),
          SizedBox(height: 10),
          _buildSectionTitle("Did you meet your goal?"),
          _buildCardContainer(height: 80, content: "Sleep goal tracker"),
        ],
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

  Widget _buildCardContainer(
      {required double height, required String content}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(content,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDropdown(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey),
      ),
      child: Text(label),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }
}
