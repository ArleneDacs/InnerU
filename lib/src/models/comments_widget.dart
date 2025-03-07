import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/user_preferences.dart';

class CommentWidget extends StatefulWidget {
  final String postId;

  const CommentWidget({super.key, required this.postId});

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  final TextEditingController _commentController = TextEditingController();

  bool _isSending = false;
  int commentCount = 0;

  get todayTasks => null;

  Future<void> addComment(String comment) async {
    String username = await UserPreferences.loadUsername() ?? "Anonymous";
    if (comment.trim().isEmpty) return;

    setState(() {
      _isSending = true;
    });

    await FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.postId)
        .collection('comments')
        .add({
      "username": username, // This will use the current logged-in user
      "comment": comment,
      "createdAt": Timestamp.now(),
    });

    setState(() {
      commentCount++;
      _commentController.clear();
      _isSending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Comments",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "$commentCount", // Magic happens here ✨
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('notes')
                    .doc(widget.postId)
                    .collection('comments')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final comments = snapshot.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        commentCount = comments.length;
                      });
                    }
                  });

                  if (comments.isEmpty) {
                    return const Center(
                      child: Text(
                        "No comments yet 🥺",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      var comment = comments[index];
                      return ListTile(
                        title: Text(
                          comment['comment'],
                          style: const TextStyle(fontSize: 16),
                        ),
                        subtitle: Text(
                          comment['username'],
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        leading: const Icon(Icons.account_circle_rounded),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context)
                    .viewInsets
                    .bottom, // This adjusts the padding dynamically
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: "Write a comment...",
                        filled: true,
                        fillColor: Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: _isSending
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.send_rounded,
                            color: Colors.deepPurple),
                    onPressed: _isSending
                        ? null
                        : () {
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
  }
}
