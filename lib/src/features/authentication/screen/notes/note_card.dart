import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onPressed;
  final VoidCallback? onChanged;

  const NoteCard({
    super.key,
    required this.note,
    required this.onPressed,
    this.onChanged,
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

  @override
  void didUpdateWidget(covariant NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent feed silently refetches posts every 20s (see
    // CommunityScreen), which hands this card a brand-new Note instance
    // with the server's current heart state. Adopt it, unless a toggle is
    // in flight right now -- otherwise a refresh landing mid-tap could
    // overwrite the optimistic UI update with the pre-tap snapshot.
    if (!_isTogglingHeart && widget.note.id == oldWidget.note.id) {
      _heartsCount = widget.note.heartsCount;
      _heartedByMe = widget.note.heartedByMe;
    }
  }

  Future<void> _toggleHeart() async {
    if (_isTogglingHeart) return;
    final wasHearted = _heartedByMe;

    setState(() {
      _isTogglingHeart = true;
      _heartedByMe = !wasHearted;
      _heartsCount = _heartsCount + (wasHearted ? -1 : 1);
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

  void openCommentSection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentWidget(
        postId: widget.note.id,
        onChanged: widget.onChanged,
      ),
    );
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
        elevation: 2,
        color: Color(widget.note.color),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
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
                  bool isLongText =
                      textContent.length > 150; // Define long text threshold

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isExpanded
                            ? textContent
                            : textContent.substring(
                                0, isLongText ? 150 : textContent.length),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color.fromARGB(221, 19, 19, 19),
                          height: 1.5,
                        ),
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
                    icon: Badge(
                      label: Text('$_heartsCount'),
                      isLabelVisible: _heartsCount > 0,
                      child: Icon(
                        _heartedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                    ),
                    color: _heartedByMe ? Colors.redAccent : Colors.black54,
                  ),
                  FutureBuilder<List<CommunityComment>>(
                    future: CommentsApiService.instance
                        .fetchComments(widget.note.id),
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
