import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';
import 'package:selfcare_projects/src/widgets/linkified_text.dart';

class CommentWidget extends StatefulWidget {
  final String postId;
  final VoidCallback? onChanged;
  final Future<List<CommunityComment>> Function()? fetchCommentsOverride;
  final Future<CommunityComment> Function(String postId, String comment)?
      addCommentOverride;

  const CommentWidget({
    super.key,
    required this.postId,
    this.onChanged,
    this.fetchCommentsOverride,
    this.addCommentOverride,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  final TextEditingController _commentController = TextEditingController();
  final CommentsApiService _api = CommentsApiService.instance;
  String? currentUsername;
  Timer? _relativeTimeTicker;
  Future<List<CommunityComment>>? _commentsFuture;
  List<CommunityComment>? _comments;

  @override
  void initState() {
    super.initState();
    _reloadComments();
    _loadCurrentUsername();
    _relativeTimeTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relativeTimeTicker?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _reloadComments() {
    setState(() {
      _comments = null;
      _commentsFuture = widget.fetchCommentsOverride != null
          ? widget.fetchCommentsOverride!()
          : _api.fetchComments(widget.postId);
    });
  }

  Future<void> _loadCurrentUsername() async {
    final username = await UserPreferences.loadUsername();
    if (!mounted) return;
    setState(() {
      currentUsername = username;
    });
  }

  DateTime _commentCreatedAt(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    return parsed?.toLocal() ?? DateTime.now();
  }

  String _formatRelativeTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.isNegative || difference.inSeconds < 60) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    if (difference.inDays < 30) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    }
    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor().clamp(1, 11);
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }

  Future<void> addComment(String comment) async {
    final trimmed = comment.trim();
    if (trimmed.isEmpty) return;

    final session = AuthService.instance.currentSession;
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = CommunityComment(
      id: tempId,
      postId: widget.postId,
      userId: session?.id.toString() ?? '',
      username: session?.name ?? 'You',
      comment: trimmed,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: null,
    );

    setState(() {
      _comments = [...(_comments ?? const <CommunityComment>[]), optimistic];
    });
    _commentController.clear();

    try {
      final saved = widget.addCommentOverride != null
          ? await widget.addCommentOverride!(widget.postId, trimmed)
          : await _api.addComment(postId: widget.postId, comment: trimmed);
      if (!mounted) return;
      // A concurrent _reloadComments() (edit/delete flow) may have nulled
      // _comments while this POST was in flight, and a fresh GET may have
      // already reseeded it from the server by the time we get here. Two
      // races are possible depending on when that GET landed relative to
      // the server actually committing this POST:
      //  - GET landed BEFORE the commit: the reseeded list has neither the
      //    tempId placeholder nor the real comment. Replacing-in-place
      //    would silently drop `saved` on the floor even though it did
      //    save successfully, so we append it instead.
      //  - GET landed AFTER the commit: the reseeded list already contains
      //    the real comment (by its real id, not tempId). Appending here
      //    would create a visible duplicate, so we do nothing.
      // If the placeholder is still present (no concurrent reload raced
      // us), replace it in place as normal.
      final currentComments = _comments;
      if (currentComments != null) {
        final hasTemp = currentComments.any((c) => c.id == tempId);
        final hasSaved = currentComments.any((c) => c.id == saved.id);
        setState(() {
          if (hasTemp) {
            _comments = [
              for (final c in currentComments)
                if (c.id == tempId) saved else c,
            ];
          } else if (!hasSaved) {
            _comments = [...currentComments, saved];
          }
          // else: reseed already includes the committed comment — nothing to do.
        });
      }
      widget.onChanged?.call();
    } catch (e) {
      debugPrint('Failed to send comment: $e');
      if (!mounted) return;
      // Same concurrent-reload guard as above: only roll back if our
      // optimistic entry could still be in the current list.
      final currentComments = _comments;
      if (currentComments != null) {
        setState(() {
          _comments = [
            for (final c in currentComments)
              if (c.id != tempId) c,
          ];
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not post your comment. Please try again.'),
        ),
      );
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _api.deleteComment(postId: widget.postId, commentId: commentId);
      _reloadComments();
      widget.onChanged?.call();
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to delete comment: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showEditDialog(
    BuildContext context,
    CommunityComment comment,
  ) {
    final TextEditingController editController =
        TextEditingController(text: comment.comment);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Comment'),
          content: TextField(
            controller: editController,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'Update your comment...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final updatedText = editController.text.trim();
                if (updatedText.isNotEmpty) {
                  await _api.updateComment(
                    postId: widget.postId,
                    commentId: comment.id,
                    comment: updatedText,
                  );
                  _reloadComments();
                  widget.onChanged?.call();
                }
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    ).then((_) => editController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return GestureDetector(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.6,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: companyTheme.inkColor,
                  ),
                ),
                Divider(color: companyTheme.mutedInkColor.withValues(alpha: 0.2)),
                Expanded(
                  child: FutureBuilder<List<CommunityComment>>(
                    future: _commentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                              ConnectionState.waiting &&
                          _comments == null) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: companyTheme.iconColor,
                          ),
                        );
                      }

                      if (snapshot.hasData && _comments == null) {
                        _comments =
                            List<CommunityComment>.from(snapshot.data!);
                      }

                      final comments = _comments ?? const <CommunityComment>[];

                      if (comments.isEmpty) {
                        return Center(
                          child: Text(
                            'No comments yet',
                            style: TextStyle(color: companyTheme.mutedInkColor),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          final formattedTime = _formatRelativeTime(
                            _commentCreatedAt(comment.createdAt),
                          );

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.account_circle_rounded,
                                  size: 40,
                                  color: companyTheme.iconColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              comment.username,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: companyTheme.inkColor,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            formattedTime,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: companyTheme.mutedInkColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: LinkifiedText(
                                              comment.comment,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: companyTheme.inkColor,
                                              ),
                                            ),
                                          ),
                                          if (currentUsername == comment.username)
                                            PopupMenuButton<String>(
                                              padding: EdgeInsets.zero,
                                              icon: Icon(
                                                Icons.more_vert,
                                                size: 18,
                                                color: companyTheme.iconColor,
                                              ),
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _showEditDialog(
                                                    context,
                                                    comment,
                                                  );
                                                } else if (value == 'delete') {
                                                  _deleteComment(comment.id);
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Delete'),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
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
                Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            maxHeight: 116,
                          ),
                          child: TextField(
                            controller: _commentController,
                            minLines: 1,
                            maxLines: 4,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: TextStyle(color: companyTheme.inkColor),
                            cursorColor: companyTheme.iconColor,
                            decoration: InputDecoration(
                              hintText: 'Write a comment...',
                              hintStyle: TextStyle(
                                color: companyTheme.mutedInkColor,
                              ),
                              filled: true,
                              fillColor: companyTheme.isDark
                                  ? companyTheme.backgroundColor
                                  : Colors.grey[200],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: companyTheme.isDark
                                      ? companyTheme.iconColor
                                          .withValues(alpha: 0.4)
                                      : Colors.transparent,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: companyTheme.isDark
                                      ? companyTheme.iconColor
                                          .withValues(alpha: 0.4)
                                      : Colors.transparent,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: companyTheme.iconColor,
                                  width: 1.4,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(
                          Icons.send_rounded,
                          color: companyTheme.iconColor,
                        ),
                        onPressed: () {
                          addComment(_commentController.text);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
