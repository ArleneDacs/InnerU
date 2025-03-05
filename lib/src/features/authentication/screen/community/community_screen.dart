import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    void cleanUpCache() async {
      Directory cacheDir =
          Directory('/data/user/0/com.example.selfcare_projects/cache');
      if (await cacheDir.exists()) {
        cacheDir.deleteSync(recursive: true);
        print("Cache Cleared! 🌱");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder(
        stream: _firestore.collection('notes').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: Colors.purple[300]),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                "No posts yet...\nShare your light with the community.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          var posts = snapshot.data!.docs.map((doc) {
            Map<String, dynamic> noteData = doc.data() as Map<String, dynamic>;
            noteData['id'] = doc.id;

            if (noteData['content'] != null) {
              noteData['content'] = List<dynamic>.from(noteData['content']);
            }

            return Note.fromMap(noteData);
          }).toList();

          return ListView.builder(
            padding: EdgeInsets.all(20),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              Note note = posts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: NoteCard(
                  note: note,
                  onPressed: () {
                    print("Tapped ${note.title}");
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
