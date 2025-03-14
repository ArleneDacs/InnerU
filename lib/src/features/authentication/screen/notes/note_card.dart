import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onPressed;

  const NoteCard({super.key, required this.note, required this.onPressed});

  Future<int> getCommentCount() async {
    QuerySnapshot comments = await FirebaseFirestore.instance
        .collection('notes')
        .doc(note.id)
        .collection('comments')
        .get();

    return comments.docs.length;
  }

  void openCommentSection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CommentWidget(
        postId: note.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime displayTime = note.createdAt;
    String formattedDateTime =
        DateFormat('h:mma MMMM d, y').format(displayTime);

    return GestureDetector(
      onTap: onPressed,
      child: Card(
        elevation: 2,
        color: Color(note.color),
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
                note.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),

              // Content Loop (Text + Images)
              ...note.note.map((item) {
                if (item["type"] == "text") {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5.0),
                    child: Text(
                      item["value"]!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color.fromARGB(221, 19, 19, 19),
                        height: 1.5,
                      ),
                    ),
                  );
                } else if (item["type"] == "image") {
                  String imageValue = item["value"]!;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.network(
                        imageValue,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                              child:
                                  CircularProgressIndicator()); // Show loader while loading
                        },
                        errorBuilder: (context, error, stackTrace) {
                          print("Image failed to load: $error"); // ✅ Debug log
                          return Icon(Icons.broken_image,
                              size: 100, color: Colors.red);
                        },
                      ),
                    ),
                  );
                }
                return const SizedBox();
              }),

              const SizedBox(height: 10),

              // Time + Buttons Row
              Row(
                children: [
                  Text(
                    '@${note.username}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formattedDateTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('notes')
                        .doc(note.id)
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
            ],
          ),
        ),
      ),
    );
  }
}
