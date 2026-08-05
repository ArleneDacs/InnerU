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
  final String? highlightCommentId;
  final Future<List<CommunityComment>> Function()? fetchCommentsOverride;
  final Future<CommunityComment> Function(String postId, String comment)?
      addCommentOverride;

  const CommentWidget({
    super.key,
    required this.postId,
    this.onChanged,
    this.highlightCommentId,
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
  final Set<String> _togglingReactionCommentIds = <String>{};
  CommunityComment? _replyingTo;

  // Per-comment GlobalKeys (top-level comments and replies share this same
  // key space, since both are rendered by _buildCommentRow) so a
  // notification-deep-linked comment can be located in the tree and
  // scrolled into view once _comments loads. Populated lazily as rows are
  // built -- see _keyFor.
  final Map<String, GlobalKey> _commentKeys = {};
  // The id of the comment currently showing its brief post-scroll pulse
  // highlight, or null when nothing is pulsing.
  String? _pulsingCommentId;
  // Attached to the comments ListView so _scrollToAndPulse can coarse-jump
  // toward a highlight target that ListView.builder hasn't built yet (see
  // that method for why a plain Scrollable.ensureVisible isn't enough).
  final ScrollController _commentsScrollController = ScrollController();
  // One-shot guard, independent of _comments's null-ness: _reloadComments()
  // (delete/edit flows) nulls _comments and reseeds it, which would
  // otherwise re-enter the seeding branch below and re-fire the scroll+
  // pulse for a highlight target that was already handled, even though the
  // reload had nothing to do with that target. Set only once the scroll+
  // pulse actually begins (see _scrollToHighlightTargetIfNeeded), so a
  // load that doesn't yet contain the target can still legitimately retry
  // on a later reseed.
  bool _hasScrolledToHighlight = false;

  GlobalKey _keyFor(String commentId) =>
      _commentKeys.putIfAbsent(commentId, () => GlobalKey());

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
    _commentsScrollController.dispose();
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

  // Scrolls to and briefly pulse-highlights widget.highlightCommentId, if
  // one was requested and it's actually present in the just-loaded
  // _comments. _comments gets reseeded (nulled, then reloaded) by
  // _reloadComments() after totally unrelated edits/deletes, which would
  // otherwise re-enter this method's `_comments == null` seeding-site call
  // and re-fire the scroll+pulse -- so _hasScrolledToHighlight guards that,
  // independent of _comments's null-ness, ensuring this only ever "fires"
  // (schedules the scroll+pulse) once per widget lifetime.
  void _scrollToHighlightTargetIfNeeded() {
    if (_hasScrolledToHighlight) return;
    final targetId = widget.highlightCommentId;
    if (targetId == null || _comments == null) return;
    final matches = _comments!.any((c) => c.id == targetId);
    if (!matches) return;

    _hasScrolledToHighlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToAndPulse(targetId));
    });
  }

  // Top-level comments the target could be anchored under, in the same
  // order _buildCommentRow's ListView.builder renders them in (i.e. the
  // order _comments came back from the backend in, filtered to
  // parentId == null). Used only to estimate the target's position for the
  // coarse scroll below.
  List<CommunityComment> _topLevelComments() =>
      (_comments ?? const <CommunityComment>[])
          .where((c) => c.parentId == null)
          .toList();

  // A reply is rendered nested inside its parent's ListView.builder item
  // (see build()'s itemBuilder), not as its own item, so the item that has
  // to be scrolled/built into view for either a top-level comment or a
  // reply is always the *top-level* one -- itself, or its parent.
  int? _topLevelIndexForHighlightTarget(String targetId) {
    final comments = _comments;
    if (comments == null) return null;
    CommunityComment? target;
    for (final c in comments) {
      if (c.id == targetId) {
        target = c;
        break;
      }
    }
    if (target == null) return null;
    final anchorId = target.parentId ?? target.id;
    final topLevel = _topLevelComments();
    for (var i = 0; i < topLevel.length; i++) {
      if (topLevel[i].id == anchorId) return i;
    }
    return null;
  }

  // ListView.builder only builds items inside the viewport plus a small
  // (~250px) cache extent, so on first frame a comment (or a reply nested
  // under one) far down a long thread has never had _buildCommentRow run
  // for it -- meaning _commentKeys has no entry for it yet, and a plain
  // Scrollable.ensureVisible has nothing to scroll to. Since the backend
  // orders comments newest-first (CommentController.php), this is a very
  // ordinary case: replying to any comment beyond the first screenful.
  //
  // Generalizes leaderboard_screen.dart's _scrollToCurrentUser: coarse-jump
  // toward an estimated position first (so the builder constructs that
  // region), then fall back to the exact Scrollable.ensureVisible once the
  // target's real GlobalKey context exists. Unlike the leaderboard's
  // fairly uniform row heights, comment rows vary a lot (reply counts,
  // text length), so instead of guessing a fixed per-row pixel height,
  // each attempt jumps to a position proportional to the target's index
  // within the flattened list, scaled by the ScrollController's own
  // running maxScrollExtent estimate -- which gets more accurate as more
  // items get built, so a few retries converge even when the first jump's
  // estimate is off.
  Future<void> _scrollToAndPulse(String targetId) async {
    GlobalKey? key = _commentKeys[targetId];

    if (key?.currentContext == null && _commentsScrollController.hasClients) {
      final targetIndex = _topLevelIndexForHighlightTarget(targetId);
      final topLevelCount = _topLevelComments().length;
      if (targetIndex != null && topLevelCount > 0) {
        const maxAttempts = 6;
        for (var attempt = 0; attempt < maxAttempts; attempt++) {
          if (!mounted || !_commentsScrollController.hasClients) break;
          final position = _commentsScrollController.position;
          final fraction =
              topLevelCount <= 1 ? 0.0 : targetIndex / (topLevelCount - 1);
          final estimated = position.minScrollExtent +
              fraction * (position.maxScrollExtent - position.minScrollExtent);
          final clamped = estimated.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          await _commentsScrollController.animateTo(
            clamped,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
          if (!mounted) return;
          // Give ListView.builder a frame to build the rows around the
          // spot we just jumped to before re-checking for the key.
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          key = _commentKeys[targetId];
          if (key?.currentContext != null) break;
        }
      }
    }

    if (!mounted) return;
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }
    if (!mounted) return;
    setState(() => _pulsingCommentId = targetId);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _pulsingCommentId = null);
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
    // Snapshot which comment (if any) this reply targets before we clear
    // _replyingTo below, so both the optimistic insert and the real
    // network call still know the parent even though the "Replying to"
    // chip has already been dismissed from the UI.
    final replyingTo = _replyingTo;
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = CommunityComment(
      id: tempId,
      postId: widget.postId,
      userId: session?.id.toString() ?? '',
      username: session?.name ?? 'You',
      comment: trimmed,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: null,
      profilePic: session?.profilePic,
      // A freshly optimistic-inserted comment doesn't exist server-side
      // yet, so it can't have any reactions on it.
      reactionsCount: 0,
      reactedByMe: false,
      parentId: replyingTo?.id,
    );

    setState(() {
      _comments = [...(_comments ?? const <CommunityComment>[]), optimistic];
      _replyingTo = null;
    });
    _commentController.clear();

    try {
      final saved = widget.addCommentOverride != null
          ? await widget.addCommentOverride!(widget.postId, trimmed)
          : await _api.addComment(
              postId: widget.postId,
              comment: trimmed,
              parentId: replyingTo?.id,
            );
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

  Future<void> _toggleReaction(CommunityComment comment) async {
    if (_togglingReactionCommentIds.contains(comment.id)) return;
    final wasReacted = comment.reactedByMe;
    final optimistic = CommunityComment(
      id: comment.id,
      postId: comment.postId,
      userId: comment.userId,
      username: comment.username,
      profilePic: comment.profilePic,
      comment: comment.comment,
      createdAt: comment.createdAt,
      updatedAt: comment.updatedAt,
      reactionsCount: comment.reactionsCount + (wasReacted ? -1 : 1),
      reactedByMe: !wasReacted,
      parentId: comment.parentId,
    );

    final beforeToggle = _comments;
    if (beforeToggle == null) return;
    setState(() {
      _togglingReactionCommentIds.add(comment.id);
      _comments = [
        for (final c in beforeToggle)
          if (c.id == comment.id) optimistic else c,
      ];
    });

    try {
      final state = wasReacted
          ? await _api.unreactComment(
              postId: widget.postId, commentId: comment.id)
          : await _api.reactComment(
              postId: widget.postId, commentId: comment.id);
      if (!mounted) return;
      // Same concurrent-reload guard as addComment: only reconcile if our
      // optimistic entry could still be in the current list.
      final currentComments = _comments;
      if (currentComments != null) {
        setState(() {
          _comments = [
            for (final c in currentComments)
              if (c.id == comment.id)
                CommunityComment(
                  id: c.id,
                  postId: c.postId,
                  userId: c.userId,
                  username: c.username,
                  profilePic: c.profilePic,
                  comment: c.comment,
                  createdAt: c.createdAt,
                  updatedAt: c.updatedAt,
                  reactionsCount: state.reactionsCount,
                  reactedByMe: state.reactedByMe,
                  parentId: c.parentId,
                )
              else
                c,
          ];
        });
      }
    } catch (e) {
      debugPrint('Failed to toggle comment reaction: $e');
      if (!mounted) return;
      final currentComments = _comments;
      if (currentComments != null) {
        setState(() {
          _comments = [
            for (final c in currentComments)
              // Roll back to the pre-tap value.
              if (c.id == comment.id) comment else c,
          ];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingReactionCommentIds.remove(comment.id);
        });
      } else {
        _togglingReactionCommentIds.remove(comment.id);
      }
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

  /// Builds a single comment's row: avatar, username, timestamp, body text,
  /// the edit/delete menu (own comments only), and the reaction/reply
  /// action row beneath it. Shared by [build] for both top-level comments
  /// and their indented replies so Tasks 4/8/10's per-row logic (optimistic
  /// state, avatars, reactions) isn't duplicated between the two.
  ///
  /// [isReply] suppresses the Reply button: replies are one level deep only
  /// (matching the backend's flat `parentId` model from Task 11), so a
  /// reply row has no parent slot for its own replies to attach to.
  Widget _buildCommentRow(
    BuildContext context,
    CompanyThemeData companyTheme,
    CommunityComment comment, {
    bool isReply = false,
  }) {
    final formattedTime = _formatRelativeTime(
      _commentCreatedAt(comment.createdAt),
    );

    return KeyedSubtree(
      key: _keyFor(comment.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: comment.id == _pulsingCommentId
            ? companyTheme.primaryColor.withValues(alpha: 0.18)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: companyTheme.iconColor.withValues(alpha: 0.15),
              backgroundImage: (comment.profilePic?.isNotEmpty ?? false)
                  ? NetworkImage(comment.profilePic!)
                  : null,
              child: (comment.profilePic?.isNotEmpty ?? false)
                  ? null
                  : Icon(
                      Icons.account_circle_rounded,
                      size: 40,
                      color: companyTheme.iconColor,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    children: [
                      InkWell(
                        onTap: _togglingReactionCommentIds.contains(comment.id)
                            ? null
                            : () => _toggleReaction(comment),
                        child: Row(
                          children: [
                            Icon(
                              comment.reactedByMe
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                              color: comment.reactedByMe
                                  ? Colors.redAccent
                                  : companyTheme.mutedInkColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${comment.reactionsCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: companyTheme.mutedInkColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isReply)
                        TextButton(
                          onPressed: () =>
                              setState(() => _replyingTo = comment),
                          child: const Text(
                            'Reply',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                Divider(
                    color: companyTheme.mutedInkColor.withValues(alpha: 0.2)),
                Expanded(
                  child: FutureBuilder<List<CommunityComment>>(
                    future: _commentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _comments == null) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: companyTheme.iconColor,
                          ),
                        );
                      }

                      if (snapshot.hasData && _comments == null) {
                        _comments = List<CommunityComment>.from(snapshot.data!);
                        // Fires exactly once per successful load: guarded by
                        // the same `_comments == null` check as the seeding
                        // assignment above, so a later rebuild (reactions,
                        // replies, the relative-time ticker, etc.) with
                        // _comments already populated never re-triggers it.
                        _scrollToHighlightTargetIfNeeded();
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

                      // Group into top-level comments plus their replies
                      // (one level deep, keyed by parentId) so replies can
                      // render indented beneath the comment they reply to.
                      final topLevelComments =
                          comments.where((c) => c.parentId == null).toList();
                      final repliesByParent =
                          <String, List<CommunityComment>>{};
                      for (final c in comments) {
                        final parentId = c.parentId;
                        if (parentId != null) {
                          (repliesByParent[parentId] ??= <CommunityComment>[])
                              .add(c);
                        }
                      }

                      return ListView.builder(
                        controller: _commentsScrollController,
                        itemCount: topLevelComments.length,
                        itemBuilder: (context, index) {
                          final comment = topLevelComments[index];
                          final replies = repliesByParent[comment.id] ??
                              const <CommunityComment>[];

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCommentRow(context, companyTheme, comment),
                              if (replies.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 40),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final reply in replies)
                                        _buildCommentRow(
                                          context,
                                          companyTheme,
                                          reply,
                                          isReply: true,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Replying to ${_replyingTo!.username}',
                            style: TextStyle(
                              fontSize: 12,
                              color: companyTheme.mutedInkColor,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: companyTheme.iconColor,
                          ),
                          onPressed: () => setState(() => _replyingTo = null),
                        ),
                      ],
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
