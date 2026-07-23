import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String selectedCategory = "Add Value";
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final String? currentUserId =
        AuthService.instance.currentSession?.id.toString();

    if (currentUserId == null) {
      return Scaffold(
        body: Center(child: Text("User not logged in.")),
      );
    }

    Query<Map<String, dynamic>> notesQuery =
        FirebaseFirestore.instance.collection('notes');

    if (selectedCategory == "Saved") {
      notesQuery = notesQuery
          .where("userId", isEqualTo: currentUserId)
          .where("saved", isEqualTo: true);
    } else if (selectedCategory == "My Post") {
      // Fetch only notes where the userId matches the current user's ID
      notesQuery = notesQuery
          .where("userId", isEqualTo: currentUserId)
          .where("saved", isEqualTo: false);
    } else {
      notesQuery = notesQuery
          .where("category", isEqualTo: selectedCategory)
          .where("saved", isEqualTo: false);
    }

    return Scaffold(
      body: Column(
        children: [
          // Category Buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ["Add Value", "Learning", "My Post", "Saved"]
                  .map((category) => _buildCategoryButton(category))
                  .toList(),
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search by username or title...",
                  prefixIcon: Icon(Icons.search, color: Colors.black),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                ),
              ),
            ),
          ),

          // Posts List
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

                // Filtering posts based on search input
                var posts = snapshot.data!.docs.map((doc) {
                  Map<String, dynamic> noteData =
                      doc.data() as Map<String, dynamic>;
                  noteData['id'] = doc.id;
                  if (noteData['note'] != null) {
                    noteData['note'] = List<dynamic>.from(noteData['note']);
                  }
                  return Note.fromMap(noteData);
                }).where((note) {
                  String username = note.username.toLowerCase();
                  String title = note.title.toLowerCase();
                  return username.contains(searchQuery) ||
                      title.contains(searchQuery);
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
                          if (note.userId == currentUserId)
                            Positioned(
                              top: 10,
                              right: 5,
                              child: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'save') {
                                    _markAsSaved(note.id);
                                  } else if (value == 'delete') {
                                    _confirmDelete(note.id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (selectedCategory != "Saved")
                                    PopupMenuItem(
                                      value: 'save',
                                      child: Row(
                                        children: [
                                          Icon(Icons.bookmark,
                                              color: Colors.blue),
                                          SizedBox(width: 8),
                                          Text("Keep Private"),
                                        ],
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text("Delete"),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (selectedCategory == "Saved")
                            Positioned(
                              top: 17,
                              right: 40,
                              child: GestureDetector(
                                onTap: () => _confirmUpload(note.id),
                                child: Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF90A17D),
                                        Color(0xFF90A17D)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF90A17D)
                                            .withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.cloud_upload_rounded,
                                    color: Colors.white,
                                    size: 20,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, 'notesType');
        },
        backgroundColor: const Color(0xFFEFD199),
        elevation: 10,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
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
          color: isSelected ? Color(0xFF90A17D) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Color(0xFF90A17D).withValues(alpha: 0.4),
                      blurRadius: 5)
                ]
              : [],
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _markAsSaved(String noteId) {
    _firestore.collection('notes').doc(noteId).update({"saved": true});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Note saved successfully")),
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
              _firestore
                  .collection('notes')
                  .doc(noteId)
                  .update({"saved": false});
              Navigator.pop(context);
            },
            child: Text("Upload", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String noteId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Note"),
        content: Text("Are you sure you want to delete this note?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text("Cancel")),
          TextButton(
            onPressed: () {
              _firestore.collection('notes').doc(noteId).delete();
              Navigator.pop(context);
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
