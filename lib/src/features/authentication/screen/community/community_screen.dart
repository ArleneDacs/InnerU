import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String selectedCategory = "Add Value";

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = _auth.currentUser?.uid;

    if (currentUserId == null) {
      return Scaffold(
        body: Center(
          child: Text("User not logged in."),
        ),
      );
    }

    Query<Map<String, dynamic>> notesQuery = _firestore.collection('notes');

    if (selectedCategory == "Saved") {
      notesQuery = notesQuery
          .where("userId", isEqualTo: currentUserId)
          .where("saved", isEqualTo: true);
    } else {
      notesQuery = notesQuery
          .where("category", isEqualTo: selectedCategory)
          .where("saved", isEqualTo: false);
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ["Add Value", "Learning", "Saved"]
                  .map((category) => _buildCategoryButton(category))
                  .toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: notesQuery.snapshots(),
              builder: (context, snapshot) {
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
                  if (noteData['note'] != null) {
                    noteData['note'] = List<dynamic>.from(noteData['note']);
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
                      child: Stack(
                        children: [
                          NoteCard(
                            note: note,
                            onPressed: () {
                              print("Tapped ${note.title}");
                            },
                          ),
                          if (selectedCategory == "Saved")
                          Positioned(
                          top: 20,
                          right: 10,
                          child: GestureDetector(
                            onTap: () => _confirmUpload(note.id),
                            child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF90A17D), Color(0xFF90A17D)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF90A17D).withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: Offset(2, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.cloud_upload_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),

                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryButton(String category) {
    bool isSelected = category == selectedCategory;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCategory = category;
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 15),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF90A17D) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [BoxShadow(color: Color(0xFF90A17D).withOpacity(0.4), blurRadius: 5)]
              : [],
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _confirmUpload(String noteId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Upload Note Publicly"),
        content: Text("Are you sure you want to upload this note publicly?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              _firestore.collection('notes').doc(noteId).update({"saved": false});
              Navigator.pop(context);
            },
            child: Text("Upload", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }
}
