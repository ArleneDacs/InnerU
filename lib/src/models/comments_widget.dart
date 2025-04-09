import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  String? currentUsername;

@override
void initState() {
  super.initState();
  _loadCurrentUsername();
}

Future<void> _loadCurrentUsername() async {
  final username = await UserPreferences.loadUsername();
  setState(() {
    currentUsername = username;
  });
}

  Future<void> addComment(String comment) async {
    if (comment.trim().isEmpty) return;

    setState(() {
      _isSending = true;
    });

    try {
      final username = await UserPreferences.loadUsername() ?? "Anonymous";
String userId = FirebaseAuth.instance.currentUser?.uid ?? "unknown";

      await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.postId)
          .collection('comments')
          .add({
        "username": username,
        "userId": userId,
        "comment": comment,
        "createdAt": Timestamp.now(),
      });

      _commentController.clear();
    } catch (e) {
      debugPrint("Failed to send comment: $e");
    }

    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  "$commentCount",
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
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notes')
                    .doc(widget.postId)
                    .collection('comments')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "No comments yet 🥺",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  final comments = snapshot.data!.docs;

                

                  return ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                 final Timestamp timestamp = comment['createdAt'] ?? Timestamp.now();
final DateTime utcTime = timestamp.toDate();
final DateTime phTime = utcTime.add(const Duration(hours: 8)); // Convert to PH Time
final String formattedTime = TimeOfDay.fromDateTime(phTime).format(context);

return Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.account_circle_rounded, size: 40),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username (takes available space)
                Expanded(
                  child: Text(
                    comment['username'] ?? "Unknown",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Time + 3-dot menu in a Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formattedTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                   
                  ],
                ),
              ],
            ),
            // The comment text and menu on the same line
            Row(
              children: [
                Expanded(
                  child: Text(
                    comment['comment'],
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // Aligning the 3-dot menu with the comment
                if (currentUsername == comment['username'])
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditDialog(context, comment);
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
                  _isSending
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.deepPurple),
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
  }
  void _deleteComment(String commentId) async {
  await FirebaseFirestore.instance
      .collection('notes')
      .doc(widget.postId)
      .collection('comments')
      .doc(commentId)
      .delete();
}

void _showEditDialog(BuildContext context, QueryDocumentSnapshot comment) {
  final TextEditingController editController = TextEditingController(text: comment['comment']);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Edit Comment"),
        content: TextField(
          controller: editController,
          maxLines: null,
          decoration: const InputDecoration(hintText: "Update your comment..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final updatedText = editController.text.trim();
              if (updatedText.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('notes')
                    .doc(widget.postId)
                    .collection('comments')
                    .doc(comment.id)
                    .update({'comment': updatedText});
              }
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
        ],
      );
    },
  );
}

}
