import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/utils/grapheme_text.dart';
import 'package:selfcare_projects/src/widgets/linkified_text.dart';
import 'package:selfcare_projects/src/widgets/member_profile_sheet.dart';

const _communityPreviewCharacterLimit = 150;

class NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onPressed;
  final VoidCallback? onChanged;
  final bool isHighlighted;

  const NoteCard({
    super.key,
    required this.note,
    required this.onPressed,
    this.onChanged,
    this.isHighlighted = false,
  });

  @override
  State<NoteCard> createState() => NoteCardState();
}

class NoteCardState extends State<NoteCard> {
  int currentPage = 0;
  bool isExpanded = false; // Track expansion state
  late int _heartsCount = widget.note.heartsCount;
  late bool _heartedByMe = widget.note.heartedByMe;
  bool _isTogglingHeart = false;
  CommunityPostLikersPage? _likerPreview;
  bool _isLoadingLikerPreview = false;
  bool _hasLoadedLikerPreview = false;
  late Future<List<CommunityComment>> _commentsFuture;

  @override
  void initState() {
    super.initState();
    _resetCommentsFuture();
  }

  @override
  void didUpdateWidget(covariant NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent feed silently refetches posts every 20s (see
    // CommunityScreen), which hands this card a brand-new Note instance
    // with the server's current heart state. Adopt it, unless a toggle is
    // in flight right now -- otherwise a refresh landing mid-tap could
    // overwrite the optimistic UI update with the pre-tap snapshot.
    if (widget.note.id != oldWidget.note.id) {
      _heartsCount = widget.note.heartsCount;
      _heartedByMe = widget.note.heartedByMe;
      _clearLikerPreview();
      _resetCommentsFuture();
      return;
    }

    if (!_isTogglingHeart) {
      _heartsCount = widget.note.heartsCount;
      _heartedByMe = widget.note.heartedByMe;
    }
  }

  void _clearLikerPreview() {
    _likerPreview = null;
    _isLoadingLikerPreview = false;
    _hasLoadedLikerPreview = false;
  }

  void _resetCommentsFuture() {
    _commentsFuture = CommentsApiService.instance.fetchComments(widget.note.id);
  }

  Future<void> _toggleHeart() async {
    if (_isTogglingHeart) return;
    final wasHearted = _heartedByMe;

    setState(() {
      _isTogglingHeart = true;
      _heartedByMe = !wasHearted;
      _heartsCount = _heartsCount + (wasHearted ? -1 : 1);
      _clearLikerPreview();
    });

    try {
      final state = wasHearted
          ? await CommunityApiService.instance.unheartPost(widget.note.id)
          : await CommunityApiService.instance.heartPost(widget.note.id);
      if (!mounted) return;
      setState(() {
        _heartsCount = state.heartsCount;
        _heartedByMe = state.heartedByMe;
      });
      widget.onChanged?.call();
    } catch (error) {
      debugPrint('Failed to toggle heart reaction: $error');
      if (!mounted) return;
      setState(() {
        // Undo exactly the optimistic delta applied above, rather than
        // trusting any other cached count, which may itself be stale.
        _heartedByMe = wasHearted;
        _heartsCount = _heartsCount + (wasHearted ? 1 : -1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your reaction.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingHeart = false;
        });
      }
    }
  }

  Future<void> _loadLikerPreview() async {
    if (_heartsCount <= 0 || _isLoadingLikerPreview || _hasLoadedLikerPreview) {
      return;
    }

    setState(() => _isLoadingLikerPreview = true);
    try {
      final page = await CommunityApiService.instance.fetchPostLikers(
        widget.note.id,
        perPage: 12,
      );
      if (!mounted) return;
      setState(() {
        _likerPreview = page;
        _hasLoadedLikerPreview = true;
        _isLoadingLikerPreview = false;
      });
    } catch (error) {
      debugPrint('Could not load post likers: $error');
      if (!mounted) return;
      setState(() => _isLoadingLikerPreview = false);
    }
  }

  String get _likerTooltip {
    if (_isLoadingLikerPreview && _likerPreview == null) {
      return 'Loading people who liked this post…';
    }

    final preview = _likerPreview;
    if (preview == null) {
      return 'Hover or tap to see who liked this post.';
    }

    if (preview.likers.isEmpty) {
      return 'No likes yet.';
    }

    final names = preview.likers.map((liker) => liker.name).join('\n');
    final remaining = preview.heartsCount - preview.likers.length;
    return remaining > 0 ? '$names\n+$remaining more' : names;
  }

  Future<void> _showLikers() async {
    if (_heartsCount <= 0) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PostLikersSheet(
        postId: widget.note.id,
        heartsCount: _heartsCount,
        initialPage: _likerPreview,
      ),
    );
  }

  Future<void> openCommentSection(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentWidget(
        postId: widget.note.id,
        onChanged: widget.onChanged,
      ),
    );
    if (!mounted) return;
    setState(_resetCommentsFuture);
  }

  void showImageDialog(String imageUrl) {
    final resolvedImageUrl =
        ImageStorageService.normalizeCommunityMediaUrl(imageUrl);
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.all(10),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              child: Image.network(
                resolvedImageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                      child: Icon(Icons.broken_image,
                          size: 100, color: Colors.red));
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime displayTime = widget.note.createdAt;
    String formattedDateTime =
        DateFormat('h:mma MMMM d, y').format(displayTime);

    List<String> imageUrls = widget.note.note
        .where((item) => item["type"] == "image")
        .map<String>(
          (item) => ImageStorageService.normalizeCommunityMediaUrl(
            item["value"],
          ),
        )
        .where((url) =>
            url.trim().isNotEmpty &&
            url != "loading" &&
            (url.startsWith("http://") || url.startsWith("https://")))
        .toList();

    return GestureDetector(
      onTap: widget.onPressed,
      child: Card(
        elevation: widget.isHighlighted ? 7 : 2,
        shadowColor: widget.isHighlighted
            ? Colors.deepPurple.withValues(alpha: 0.38)
            : null,
        color: Color(widget.note.color),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: widget.isHighlighted
              ? const BorderSide(color: Colors.deepPurple, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isHighlighted)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'From your notification',
                    style: TextStyle(
                      color: Colors.deepPurple,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              // Title
              EmojiAwareText(
                widget.note.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Content (Text + Images)
              ...widget.note.note.map((item) {
                if (item["type"] == "text") {
                  String textContent = item["value"]!;
                  final collapsedText = truncateToGraphemeClusters(
                    textContent,
                    _communityPreviewCharacterLimit,
                  );
                  final isLongText = collapsedText != textContent;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinkifiedText(
                        isExpanded ? textContent : collapsedText,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color.fromARGB(221, 19, 19, 19),
                          height: 1.5,
                        ),
                        mentions: widget.note.mentions
                            .map((m) => MentionSpanTarget(
                                  userId: m['userId'] ?? '',
                                  name: m['name'] ?? '',
                                ))
                            .toList(),
                        mentionStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                        onMentionTap: (userId) {
                          final mention = widget.note.mentions.firstWhere(
                            (m) => m['userId'] == userId,
                            orElse: () => const <String, String>{},
                          );
                          showMemberProfileSheet(
                            context,
                            userId: userId,
                            name: mention['name'] ?? 'Member',
                          );
                        },
                      ),
                      if (isLongText)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              isExpanded = !isExpanded; // Toggle expansion
                            });
                          },
                          child: Text(
                            isExpanded ? "Read Less" : "Read More...",
                            style: TextStyle(
                              color: const Color.fromARGB(255, 165, 165, 165),
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return const SizedBox();
              }),
              const SizedBox(height: 20),
              if (imageUrls.isNotEmpty)
                Column(
                  children: [
                    SizedBox(
                      height: 200,
                      child: Stack(
                        children: [
                          SizedBox(
                            height: 200,
                            child: PageView.builder(
                              itemCount: imageUrls.length,
                              onPageChanged: (int page) {
                                setState(() {
                                  currentPage = page;
                                });
                              },
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onTap: () =>
                                      showImageDialog(imageUrls[index]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.network(
                                      imageUrls[index],
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return const Center(
                                            child: CircularProgressIndicator());
                                      },
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          width: double.infinity,
                                          height: 200,
                                          color: Colors.black12,
                                          child: const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons
                                                      .image_not_supported_rounded,
                                                  size: 54,
                                                  color: Colors.black54,
                                                ),
                                                SizedBox(height: 8),
                                                Text(
                                                  'Image unavailable',
                                                  style: TextStyle(
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // Image Counter (Only if there are multiple images)
                          if (imageUrls.length > 1)
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${currentPage + 1}/${imageUrls.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Page Indicator (Max 4 dots visible)
                    if (imageUrls.length > 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            imageUrls.length > 4
                                ? 4
                                : imageUrls.length, // Limit to 4
                            (index) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                width: (currentPage % 4 == index)
                                    ? 16
                                    : 8, // Highlight current
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: (currentPage % 4 == index)
                                      ? Colors.black
                                      : Colors.grey[400],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 10),

              // Time + Buttons Row
              Row(
                children: [
                  // Username (Left-Aligned)
                  Text(
                    '@${widget.note.username}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(), // Pushes the next content to the right
                  IconButton(
                    onPressed: _isTogglingHeart ? null : _toggleHeart,
                    tooltip: _heartedByMe ? 'Unlike' : 'Like',
                    icon: Icon(
                      _heartedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                    color: _heartedByMe ? Colors.redAccent : Colors.black54,
                  ),
                  if (_heartsCount > 0)
                    Tooltip(
                      message: _likerTooltip,
                      waitDuration: const Duration(milliseconds: 350),
                      child: MouseRegion(
                        onEnter: (_) => unawaited(_loadLikerPreview()),
                        child: Semantics(
                          button: true,
                          label:
                              '$_heartsCount ${_heartsCount == 1 ? 'person' : 'people'} liked this post. Show names.',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => unawaited(_showLikers()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 7,
                              ),
                              child: Text(
                                '$_heartsCount',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  FutureBuilder<List<CommunityComment>>(
                    future: _commentsFuture,
                    builder: (context, snapshot) {
                      final commentCount = snapshot.data?.length ?? 0;
                      if (!snapshot.hasData) {
                        return IconButton(
                          onPressed: () => openCommentSection(context),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          color: Colors.black54,
                        );
                      }

                      return IconButton(
                        onPressed: () => openCommentSection(context),
                        icon: Badge(
                          label: Text('$commentCount'),
                          child: const Icon(Icons.chat_bubble_outline_rounded),
                        ),
                        color: Colors.black54,
                      );
                    },
                  ),
                ],
              ),

              // Centered Date and Time
              const SizedBox(height: 4),
              Center(
                child: Text(
                  formattedDateTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tap counterpart to the desktop hover tooltip.  It keeps loading in
/// small pages, so a post with many hearts stays responsive on mobile and web
/// instead of downloading an unbounded list just to render a count.
class _PostLikersSheet extends StatefulWidget {
  const _PostLikersSheet({
    required this.postId,
    required this.heartsCount,
    this.initialPage,
  });

  final String postId;
  final int heartsCount;
  final CommunityPostLikersPage? initialPage;

  @override
  State<_PostLikersSheet> createState() => _PostLikersSheetState();
}

class _PostLikersSheetState extends State<_PostLikersSheet> {
  final ScrollController _scrollController = ScrollController();
  late List<CommunityPostLiker> _likers;
  late int _nextPage;
  late int _heartsCount;
  late bool _hasMore;
  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  Object? _initialError;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPage;
    _likers = List<CommunityPostLiker>.from(initial?.likers ?? const []);
    _nextPage = (initial?.page ?? 0) + 1;
    _heartsCount = initial?.heartsCount ?? widget.heartsCount;
    _hasMore = initial?.hasMore ?? true;
    _scrollController.addListener(_onScroll);

    if (initial == null) {
      unawaited(_loadInitial());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels >
            120) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadInitial() async {
    if (_isLoadingInitial) return;
    setState(() {
      _isLoadingInitial = true;
      _initialError = null;
    });

    try {
      final page = await CommunityApiService.instance.fetchPostLikers(
        widget.postId,
        page: 1,
        perPage: 20,
      );
      if (!mounted) return;
      setState(() {
        _likers = page.likers;
        _heartsCount = page.heartsCount;
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
        _isLoadingInitial = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingInitial = false;
        _initialError = error;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingInitial || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _moreError = null;
    });

    try {
      final page = await CommunityApiService.instance.fetchPostLikers(
        widget.postId,
        page: _nextPage,
        perPage: 20,
      );
      if (!mounted) return;

      final knownIds = _likers.map((liker) => liker.id).toSet();
      final additions = page.likers
          .where((liker) => liker.id.isEmpty || knownIds.add(liker.id))
          .toList();
      setState(() {
        _likers = [..._likers, ...additions];
        _heartsCount = page.heartsCount;
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _moreError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (screenHeight < 340
            ? screenHeight * 0.9
            : (screenHeight * 0.58).clamp(300.0, 520.0))
        .toDouble();

    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$_heartsCount ${_heartsCount == 1 ? 'like' : 'likes'}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoadingInitial && _likers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_initialError != null && _likers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load people who liked this post.'),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadInitial, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_likers.isEmpty) {
      return const Center(child: Text('No likes yet.'));
    }

    return ListView(
      controller: _scrollController,
      children: [
        for (final liker in _likers)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.12),
              foregroundColor: theme.colorScheme.primary,
              child: Text(
                liker.name.isEmpty
                    ? '?'
                    : liker.name.substring(0, 1).toUpperCase(),
              ),
            ),
            title: Text(liker.name),
          ),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_moreError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Could not load more. Retry'),
              ),
            ),
          ),
      ],
    );
  }
}
