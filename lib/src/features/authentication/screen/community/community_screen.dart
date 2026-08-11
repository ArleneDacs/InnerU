import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/notes/note_card.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.targetPostId,
    this.targetCommentId,
    this.showStandaloneAppBar = true,
  });

  /// When set, this post is brought into view and highlighted once the feed
  /// finishes its initial load (used by deep links from push notifications).
  final String? targetPostId;

  /// Optional comment to highlight inside the opened comment sheet, wired
  /// through [_openCommentsFor] into [CommentWidget.highlightCommentId].
  final String? targetCommentId;

  /// The bottom-navigation shell already owns the Community app bar. A
  /// notification opens this screen as its own route, where it needs its own
  /// app bar to keep the content below the system/header area and provide a
  /// way back.
  final bool showStandaloneAppBar;

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
  String? _highlightedPostId;
  Note? _focusedPost;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialPosts());
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

  // Kicks off the initial load and, once it lands, focuses any post supplied
  // by a notification deep link.
  Future<void> _loadInitialPosts() async {
    await _loadPosts(showSpinner: true);
    await _openTargetIfNeeded();
  }

  // Community notifications are not scoped to the default "Add Value" tab.
  // Resolve the one post directly, put it visibly at the top of the feed,
  // and visually mark it.  A comment sheet is only opened for notifications
  // that actually target a comment; a heart should focus the post itself.
  Future<void> _openTargetIfNeeded() async {
    final targetPostId = widget.targetPostId?.trim();
    if (targetPostId == null || targetPostId.isEmpty) return;

    var target = _posts.firstWhereOrNull((post) => post.id == targetPostId);

    if (target == null) {
      try {
        target = await CommunityApiService.instance.fetchPost(targetPostId);
      } catch (error) {
        // An older deployment may not have the targeted-show endpoint yet.
        // Keep a bounded best-effort fallback for that transition rather than
        // turning a notification tap into a dead end.
        try {
          final allPosts = await CommunityApiService.instance.fetchPosts();
          target = allPosts.firstWhereOrNull((post) => post.id == targetPostId);
        } catch (fallbackError) {
          debugPrint(
            'Could not resolve deep-linked community post: $error / $fallbackError',
          );
          return;
        }
      }
    }

    if (target == null || !mounted) return;
    final resolvedTarget = target;
    _focusPost(resolvedTarget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.targetCommentId != null &&
          widget.targetCommentId!.isNotEmpty) {
        _openCommentsFor(
          resolvedTarget,
          highlightCommentId: widget.targetCommentId,
        );
      }
    });
  }

  String? _targetCategoryFor(Note post) {
    if (post.saved) return 'Saved';
    if (post.category == 'Add Value' || post.category == 'Learning') {
      return post.category;
    }
    return null;
  }

  List<Note> _prioritizeFocusedPost(List<Note> posts) {
    final focused = _focusedPost;
    if (focused == null || _highlightedPostId != focused.id) return posts;

    final fresh =
        posts.firstWhereOrNull((post) => post.id == focused.id) ?? focused;
    return [fresh, ...posts.where((post) => post.id != fresh.id)];
  }

  void _focusPost(Note post) {
    final targetCategory = _targetCategoryFor(post);
    final categoryChanged =
        targetCategory != null && targetCategory != selectedCategory;

    setState(() {
      if (targetCategory != null) {
        selectedCategory = targetCategory;
      }
      _focusedPost = post;
      _highlightedPostId = post.id;
      _posts = _prioritizeFocusedPost(_posts);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });

    if (categoryChanged) {
      unawaited(_reloadFocusedCategory(post, targetCategory));
    }
  }

  Future<void> _reloadFocusedCategory(Note target, String category) async {
    try {
      final posts =
          await CommunityApiService.instance.fetchPosts(category: category);
      if (!mounted || selectedCategory != category) return;
      final freshTarget =
          posts.firstWhereOrNull((post) => post.id == target.id) ?? target;
      setState(() {
        _focusedPost = freshTarget;
        _posts = _prioritizeFocusedPost(posts);
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || selectedCategory != category) return;
      setState(() {
        // The directly fetched target is still usable, so do not replace it
        // with a full-screen error if its category refresh happens to fail.
        _isLoading = false;
      });
      debugPrint('Could not refresh the notification post category: $error');
    }
  }

  // Mirrors NoteCardState.openCommentSection (see note_card.dart). That
  // method is an instance method tightly coupled to NoteCard's own state
  // (widget.note, widget.onChanged), so it isn't reasonably extractable
  // into a shared free function -- duplicating the showModalBottomSheet
  // call here is the pragmatic choice.
  void _openCommentsFor(Note post, {String? highlightCommentId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentWidget(
        postId: post.id,
        onChanged: _refreshPosts,
        highlightCommentId: highlightCommentId,
      ),
    );
  }

  Future<void> _loadPosts({bool showSpinner = false}) async {
    // Keep a late response for a previous tab from replacing the focused post
    // (or the current tab) while a notification target is being resolved.
    final requestedCategory = selectedCategory;
    if (showSpinner && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final posts = await CommunityApiService.instance.fetchPosts(
        category: requestedCategory,
      );
      if (!mounted || selectedCategory != requestedCategory) return;
      setState(() {
        _posts = _prioritizeFocusedPost(posts);
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || selectedCategory != requestedCategory) return;
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
      _highlightedPostId = null;
      _focusedPost = null;
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

  List<Map<String, String>> _editedNoteContent(
    Note post,
    List<TextEditingController> textControllers,
  ) {
    var textIndex = 0;
    final updated = <Map<String, String>>[];
    for (final item in post.note) {
      final copy = Map<String, String>.from(item);
      if (copy['type'] == 'text' && textIndex < textControllers.length) {
        copy['value'] = textControllers[textIndex].text.trim();
        textIndex += 1;
      }
      updated.add(copy);
    }

    // Older/imported image-only posts have no editable text segment.  Add one
    // without touching the existing media so the author can still add a body.
    if (textIndex == 0 && textControllers.isNotEmpty) {
      updated.insert(0, {
        'type': 'text',
        'value': textControllers.first.text.trim(),
      });
    }
    return updated;
  }

  bool _matchesSelectedCategory(Note post, String currentUserId) {
    switch (selectedCategory) {
      case 'Saved':
        return post.saved && post.userId == currentUserId;
      case 'My Post':
        return !post.saved && post.userId == currentUserId;
      default:
        return !post.saved && post.category == selectedCategory;
    }
  }

  void _applyEditedPost(Note updated) {
    final currentUserId = AuthService.instance.currentSession?.id.toString();
    if (currentUserId == null) return;

    setState(() {
      final existingIndex = _posts.indexWhere((post) => post.id == updated.id);
      if (_matchesSelectedCategory(updated, currentUserId)) {
        if (existingIndex == -1) {
          _posts = [updated, ..._posts];
        } else {
          final nextPosts = List<Note>.from(_posts);
          nextPosts[existingIndex] = updated;
          _posts = nextPosts;
        }
      } else if (existingIndex != -1) {
        final nextPosts = List<Note>.from(_posts);
        nextPosts.removeAt(existingIndex);
        _posts = nextPosts;
      }

      if (_focusedPost?.id == updated.id) {
        _focusedPost = updated;
      }
    });
  }

  Future<void> _editPost(Note post) async {
    final titleController = TextEditingController(text: post.title);
    final textControllers = post.note
        .where((item) => item['type'] == 'text')
        .map((item) => TextEditingController(text: item['value'] ?? ''))
        .toList();
    if (textControllers.isEmpty) {
      textControllers.add(TextEditingController());
    }

    final categories = <String>['Add Value', 'Learning'];
    var selectedEditCategory = post.category;
    if (!categories.contains(selectedEditCategory)) {
      categories.insert(0, selectedEditCategory);
    }

    Note? updated;
    try {
      updated = await showDialog<Note>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isSaving = false;
          String? saveError;

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final hasBody = textControllers.any(
                (controller) => controller.text.trim().isNotEmpty,
              );
              final isValid = titleController.text.trim().isNotEmpty &&
                  selectedEditCategory.trim().isNotEmpty &&
                  hasBody;

              Future<void> saveEdit() async {
                if (!isValid || isSaving) return;
                setDialogState(() {
                  isSaving = true;
                  saveError = null;
                });

                try {
                  final saved = await CommunityApiService.instance.updatePost(
                    postId: post.id,
                    title: titleController.text.trim(),
                    category: selectedEditCategory,
                    note: _editedNoteContent(post, textControllers),
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop(saved);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSaving = false;
                    saveError = 'Could not update this post: $error';
                  });
                }
              }

              return AlertDialog(
                title: const Text('Edit post'),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: titleController,
                          enabled: !isSaving,
                          maxLength: 50,
                          onChanged: (_) => setDialogState(() {}),
                          decoration: const InputDecoration(labelText: 'Title'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedEditCategory,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          items: categories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: isSaving
                              ? null
                              : (category) {
                                  if (category == null) return;
                                  setDialogState(
                                    () => selectedEditCategory = category,
                                  );
                                },
                        ),
                        const SizedBox(height: 12),
                        for (var index = 0;
                            index < textControllers.length;
                            index++) ...[
                          TextField(
                            controller: textControllers[index],
                            enabled: !isSaving,
                            minLines: 4,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: textControllers.length == 1
                                  ? 'Post content'
                                  : 'Post content ${index + 1}',
                              alignLabelWithHint: true,
                            ),
                          ),
                          if (index + 1 < textControllers.length)
                            const SizedBox(height: 12),
                        ],
                        if (saveError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            saveError!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isValid && !isSaving ? saveEdit : null,
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      for (final controller in textControllers) {
        controller.dispose();
      }
    }

    if (!mounted || updated == null) return;
    _applyEditedPost(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Post updated.')),
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
            appBar: widget.showStandaloneAppBar
                ? AppBar(
                    backgroundColor: companyTheme.surfaceColor,
                    foregroundColor: companyTheme.inkColor,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    title: const Text('Community'),
                  )
                : null,
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
                                  isHighlighted: note.id == _highlightedPostId,
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
                                        if (value == 'edit') {
                                          unawaited(_editPost(note));
                                        } else if (value == 'save') {
                                          _markAsSaved(note.id);
                                        } else if (value == 'delete') {
                                          _confirmDelete(note.id);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.edit_outlined,
                                                color: Colors.deepPurple,
                                              ),
                                              SizedBox(width: 8),
                                              Text('Edit'),
                                            ],
                                          ),
                                        ),
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
