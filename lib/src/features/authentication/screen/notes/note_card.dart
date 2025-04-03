import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onPressed;

  const NoteCard({super.key, required this.note, required this.onPressed});

  @override
  _NoteCardState createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  int currentPage = 0;
  bool isExpanded = false; // Track expansion state

  void openCommentSection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentWidget(
        postId: widget.note.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime displayTime = widget.note.createdAt;
    String formattedDateTime = DateFormat('h:mma MMMM d, y').format(displayTime);

    List<String> imageUrls = widget.note.note
        .where((item) => item["type"] == "image")
        .map<String>((item) => item["value"]!)
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
                  bool isLongText = textContent.length > 150; // Define long text threshold

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isExpanded ? textContent : textContent.substring(0, isLongText ? 150 : textContent.length),
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
            PageView.builder(
              itemCount: imageUrls.length,
              onPageChanged: (index) {
                setState(() {
                  currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    imageUrls[index],
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.broken_image, size: 100, color: Colors.red);
                    },
                  ),
                );
              },
            ),

            // Image Counter (Only if there are multiple images)
            if (imageUrls.length > 1)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              imageUrls.length > 4 ? 4 : imageUrls.length, // Limit to 4
              (index) {
                int startIndex = (currentPage ~/ 4) * 4; // Dynamic start index

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: (currentPage % 4 == index) ? 16 : 8, // Highlight current
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: (currentPage % 4 == index) ? Colors.black : Colors.grey[400],
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
                  StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('notes')
                        .doc(widget.note.id)
                        .collection('comments')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return IconButton(
                          onPressed: () => openCommentSection(context),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          color: Colors.black54,
                        );
                      }
                      int commentCount = snapshot.data!.docs.length;

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
