import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';

class CommentWidget extends StatefulWidget {
  final String postId;

  const CommentWidget({super.key, required this.postId});

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  final TextEditingController _commentController = TextEditingController();
  final CommentsApiService _api = CommentsApiService.instance;
  bool _isSending = false;
  String? currentUsername;
  Timer? _relativeTimeTicker;
  Future<List<CommunityComment>>? _commentsFuture;

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
      _commentsFuture = _api.fetchComments(widget.postId);
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
    if (comment.trim().isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await _api.addComment(postId: widget.postId, comment: comment.trim());
      _commentController.clear();
      _reloadComments();
    } catch (e) {
      debugPrint('Failed to send comment: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _api.deleteComment(postId: widget.postId, commentId: commentId);
      _reloadComments();
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
                      final comments = snapshot.data ?? const <CommunityComment>[];
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          comments.isEmpty) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: companyTheme.iconColor,
                          ),
                        );
                      }

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
                                            child: Text(
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
                      _isSending
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: companyTheme.iconColor,
                              ),
                            )
                          : IconButton(
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
