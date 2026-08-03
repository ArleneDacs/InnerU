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
  final ScrollController _scrollController = ScrollController();
  String searchQuery = '';
  List<Note> _posts = <Note>[];
  bool _isLoading = true;
  String? _loadError;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPosts(showSpinner: true));
    // The feed used to hold a Future<List<Note>> that FutureBuilder awaited
    // directly, so every periodic refresh swapped it for a new, pending
    // Future -- which made FutureBuilder briefly render its "waiting"
    // branch (a centered spinner) in place of the list. That tore down and
    // recreated the ListView every 20 seconds, and a freshly created
    // ListView always starts scrolled to the top, which is what read as the
    // feed "jumping back to the top" while someone was reading it. Loading
    // into this _posts list instead means the periodic refresh only updates
    // the data the already-mounted ListView is displaying -- the list
    // itself, and its scroll position, never gets torn down.
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_refreshPosts());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts({bool showSpinner = false}) async {
    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final posts = await CommunityApiService.instance.fetchPosts(
        category: selectedCategory,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = error.toString();
      });
    }
  }

  // Silent background refresh: reloads data in place without flashing the
  // loading spinner or otherwise disturbing whatever the user is doing
  // (e.g. reading a post further down the feed).
  Future<void> _refreshPosts() => _loadPosts();

  Future<void> _selectCategory(String category) async {
    if (category == selectedCategory) return;
    setState(() {
      selectedCategory = category;
    });
    // Switching categories is a deliberate navigation action, unlike the
    // periodic background refresh, so resetting to the top of the (new)
    // list here is expected rather than the bug being fixed above.
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadPosts(showSpinner: true);
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
                  child: Builder(
                    builder: (context) {
                      // Only the very first load (or a deliberate category
                      // switch) has no posts to show yet, so only those
                      // show the spinner in place of the list. The 20s
                      // background refresh leaves _posts (and therefore the
                      // mounted ListView and its scroll offset) alone until
                      // the new data actually arrives.
                      if (_isLoading && _posts.isEmpty) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: companyTheme.primaryColor,
                          ),
                        );
                      }

                      if (_loadError != null && _posts.isEmpty) {
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

                      final posts = _posts.where((note) {
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
                        controller: _scrollController,
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
      onTap: () => unawaited(_selectCategory(category)),
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
