import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String selectedCategory = 'Add Value';
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  Future<List<Note>>? _postsFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      _refreshPosts();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Note>> _loadPosts() {
    return CommunityApiService.instance.fetchPosts(
      category: selectedCategory,
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
        const SnackBar(content: Text('Note saved successfully')),
      );
      await _refreshPosts();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save note: $error')),
      );
    }
  }

  void _confirmUpload(String noteId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upload Note Publicly'),
        content: const Text('Are you sure you want to upload this note publicly?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext);
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
                  SnackBar(content: Text('Could not upload note: $error')),
                );
              }
            },
            child: const Text(
              'Upload',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String noteId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext);
              try {
                await CommunityApiService.instance.deletePost(noteId);
                if (!mounted) return;
                await _refreshPosts();
              } catch (error) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not delete note: $error')),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.instance.currentSession?.id.toString();
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in.')),
      );
    }

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            body: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['Add Value', 'Learning', 'My Post', 'Saved']
                        .map(
                          (category) => _buildCategoryButton(
                            category,
                            companyTheme,
                          ),
                        )
                        .toList(),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: companyTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: companyTheme.primaryColor.withValues(alpha: 0.18),
                          blurRadius: 6,
                          offset: const Offset(2, 2),
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
                        hintText: 'Search by username or title...',
                        prefixIcon: Icon(
                          Icons.search,
                          color: companyTheme.inkColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: companyTheme.surfaceColor,
                      ),
                      style: TextStyle(color: companyTheme.inkColor),
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Note>>(
                    future: _postsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: companyTheme.primaryColor,
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load community posts from InnerU.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: companyTheme.mutedInkColor,
                              ),
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
                      }).toList();

                      if (posts.isEmpty) {
                        return Center(
                          child: Text(
                            'No posts yet...\nShare your light with the community.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: companyTheme.mutedInkColor,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          final note = posts[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Stack(
                              children: [
                                NoteCard(
                                  note: note,
                                  onPressed: () {
                                    debugPrint('Tapped ${note.title}');
                                  },
                                  onChanged: _refreshPosts,
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
                                        if (selectedCategory != 'Saved')
                                          const PopupMenuItem(
                                            value: 'save',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.bookmark,
                                                  color: Colors.blue,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Keep Private'),
                                              ],
                                            ),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Delete'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (selectedCategory == 'Saved')
                                  Positioned(
                                    top: 17,
                                    right: 40,
                                    child: GestureDetector(
                                      onTap: () => _confirmUpload(note.id),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF90A17D),
                                              Color(0xFF90A17D),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF90A17D)
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 6,
                                              offset: const Offset(2, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
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
              backgroundColor: companyTheme.primaryColor,
              foregroundColor: companyTheme.inkColor,
              elevation: 10,
              shape: const CircleBorder(),
              child: const Icon(Icons.add),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryButton(
    String category,
    CompanyThemeData companyTheme,
  ) {
    final isSelected = category == selectedCategory;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedCategory = category;
          _postsFuture = _loadPosts();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
        decoration: BoxDecoration(
          color: isSelected
              ? companyTheme.primaryColor
              : companyTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: companyTheme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 5,
                  ),
                ]
              : const [],
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected
                ? companyTheme.inkColor
                : companyTheme.mutedInkColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
