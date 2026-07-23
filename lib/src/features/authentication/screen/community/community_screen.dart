import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/app_route_observer.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with RouteAware {
  final CommunityApiService _api = CommunityApiService.instance;
  final TextEditingController _searchController = TextEditingController();
  ModalRoute<dynamic>? _route;

  String selectedCategory = 'Add Value';
  String searchQuery = '';
  List<Note> _posts = const <Note>[];
  bool _isLoading = true;

  String? get _currentUserId =>
      AuthService.instance.currentSession?.id.toString();

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _route = null;
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final posts = await _api.fetchPosts(category: selectedCategory);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posts = const <Note>[];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load community posts: $e')),
      );
    }
  }

  List<Note> _filteredPosts() {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _posts;

    return _posts.where((note) {
      final username = note.username.toLowerCase();
      final title = note.title.toLowerCase();
      return username.contains(query) || title.contains(query);
    }).toList();
  }

  Future<void> _markAsSaved(String postId) async {
    try {
      await _api.setSaved(postId: postId, saved: true);
      await _loadPosts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save post: $e')),
      );
    }
  }

  Future<void> _confirmUpload(String postId) async {
    final shouldUpload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make Post Public'),
        content: const Text('Do you want to move this post back to public?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (shouldUpload != true) return;

    try {
      await _api.setSaved(postId: postId, saved: false);
      await _loadPosts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update post: $e')),
      );
    }
  }

  Future<void> _confirmDelete(String postId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('This will permanently remove the post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await _api.deletePost(postId);
      await _loadPosts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete post: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in.')),
      );
    }

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        final visiblePosts = _filteredPosts();

        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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
                      color: companyTheme.isDark
                          ? companyTheme.surfaceColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: companyTheme.isDark
                            ? companyTheme.iconColor.withValues(alpha: 0.42)
                            : Colors.transparent,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: companyTheme.isDark ? 0.22 : 0.08,
                          ),
                          blurRadius: 8,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: companyTheme.inkColor),
                      cursorColor: companyTheme.iconColor,
                      onChanged: (value) {
                        setState(() {
                          searchQuery = value.toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by username or title...',
                        hintStyle: TextStyle(color: companyTheme.mutedInkColor),
                        prefixIcon: Icon(
                          Icons.search,
                          color: companyTheme.iconColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: companyTheme.isDark
                            ? companyTheme.surfaceColor
                            : Colors.grey[200],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadPosts,
                    child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: companyTheme.iconColor,
                            ),
                          )
                        : visiblePosts.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height *
                                            0.55,
                                    child: Center(
                                      child: Text(
                                        'No posts yet...\nShare your light with the community.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: companyTheme.mutedInkColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                itemCount: visiblePosts.length,
                                itemBuilder: (context, index) {
                                  final note = visiblePosts[index];
                                  final isOwner = note.userId == currentUserId;

                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 20),
                                    child: Stack(
                                      children: [
                                        NoteCard(
                                          note: note,
                                          onPressed: () {},
                                          onChanged: _loadPosts,
                                        ),
                                        if (isOwner)
                                          Positioned(
                                            top: 10,
                                            right: 5,
                                            child: PopupMenuButton<String>(
                                              iconColor: companyTheme.iconColor,
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
                                                        Icon(Icons.bookmark,
                                                            color: Colors.blue),
                                                        SizedBox(width: 8),
                                                        Text('Keep Private'),
                                                      ],
                                                    ),
                                                  ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete,
                                                          color: Colors.red),
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
                                              onTap: () =>
                                                  _confirmUpload(note.id),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      companyTheme.iconColor,
                                                      companyTheme.iconColor,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: companyTheme
                                                          .iconColor
                                                          .withValues(
                                                              alpha: 0.3),
                                                      blurRadius: 6,
                                                      offset:
                                                          const Offset(2, 2),
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
                              ),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.pushNamed(context, 'notesType');
            },
            backgroundColor: companyTheme.isDark
                ? companyTheme.iconColor
                : const Color(0xFFEFD199),
            elevation: 10,
            shape: const CircleBorder(),
            child: Icon(
              Icons.add,
              color: companyTheme.isDark ? Colors.black : Colors.white,
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
        });
        _loadPosts();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
        decoration: BoxDecoration(
          color: isSelected
              ? companyTheme.iconColor
              : companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: companyTheme.isDark
                ? companyTheme.iconColor.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: companyTheme.iconColor.withValues(alpha: 0.28),
                    blurRadius: 5,
                  )
                ]
              : [],
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected
                ? (companyTheme.isDark ? Colors.black : Colors.white)
                : companyTheme.inkColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
