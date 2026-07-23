import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String selectedCategory = "Add Value";
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";
  Future<List<Note>>? _postsFuture;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Note>> _loadPosts() {
    final category =
        selectedCategory == "Add Value" || selectedCategory == "Learning"
            ? selectedCategory
            : selectedCategory;
    return CommunityApiService.instance.fetchPosts(
      category: category,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId =
        AuthService.instance.currentSession?.id.toString();

    if (currentUserId == null) {
      return Scaffold(
        body: Center(child: Text("User not logged in.")),
      );
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
            child: FutureBuilder<List<Note>>(
              future: _postsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: Colors.purple[300]),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load community posts from InnerU.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                    ),
                  );
                }

                final posts = (snapshot.data ?? const <Note>[])
                    .where((note) {
                      final username = note.username.toLowerCase();
                      final title = note.title.toLowerCase();
                      return username.contains(searchQuery) ||
                          title.contains(searchQuery);
                    })
                    .toList();

                if (posts.isEmpty) {
                  return Center(
                    child: Text(
                      "No posts yet...\nShare your light with the community.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

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
                              debugPrint("Tapped ${note.title}");
                            },
                            onChanged: () {
                              setState(() {
                                _postsFuture = _loadPosts();
                              });
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
                                    const PopupMenuItem(
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
                                  const PopupMenuItem(
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
          _postsFuture = _loadPosts();
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

  Future<void> _refreshPosts() async {
    if (!mounted) return;
    setState(() {
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _markAsSaved(String noteId) async {
    try {
      await CommunityApiService.instance.setSaved(
        postId: noteId,
        saved: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Note saved successfully")),
      );
      await _refreshPosts();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not save note: $error")),
      );
    }
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
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await CommunityApiService.instance.setSaved(
                  postId: noteId,
                  saved: false,
                );
                if (!mounted) return;
                await _refreshPosts();
              } catch (error) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text("Could not upload note: $error")),
                );
              }
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
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await CommunityApiService.instance.deletePost(noteId);
                if (!mounted) return;
                await _refreshPosts();
              } catch (error) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text("Could not delete note: $error")),
                );
              }
            },
            child: Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
