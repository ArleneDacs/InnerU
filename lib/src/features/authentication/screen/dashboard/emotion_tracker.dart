import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmotionTrackerPage extends StatefulWidget {
  @override
  _EmotionTrackerPageState createState() => _EmotionTrackerPageState();
}

class _EmotionTrackerPageState extends State<EmotionTrackerPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Emotion Tracker')),
        body: Center(child: Text('User not logged in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Emotion Tracker'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('emotions')
            .where('userId', isEqualTo: user.uid)
            // Remove orderBy temporarily if error persists
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
                child: Text('Error fetching emotions: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No emotions recorded.'));
          }

          List<Map<String, dynamic>> emotions = snapshot.data!.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList();

          return ListView.builder(
            itemCount: emotions.length,
            itemBuilder: (context, index) {
              var emotion = emotions[index];
              return ListTile(
                leading: Icon(Icons.mood),
                title: Text(emotion['emotion']),
                subtitle: Text("Date: ${emotion['date']}"),
              );
            },
          );
        },
      ),
    );
  }
}
