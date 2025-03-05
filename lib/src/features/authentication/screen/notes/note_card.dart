import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onPressed;

  const NoteCard({super.key, required this.note, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    DateTime displayTime = note.createdAt;
    String formattedDateTime =
        DateFormat('h:mma MMMM d, y').format(displayTime);

    return GestureDetector(
      onTap: onPressed,
      child: Card(
        elevation: 4,
        color: Color(note.color),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                note.title,
                style: TextStyle(
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
                      item["value"],
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  );
                } else if (item["type"] == "image") {
                  String imagePath = item["value"]
                      .toString()
                      .replaceAll('"', '')
                      .replaceAll('%22', '');
                  bool isLocalFile = imagePath.contains("/data/user/0");
                  if (imagePath.contains("FileImage(")) {
                    imagePath = imagePath.split("(")[1].split(",")[0];
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: isLocalFile
                          ? Image.file(
                              File(imagePath
                                  .trim()
                                  .replaceAll("file://", "")
                                  .replaceAll('"', '')),
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              imagePath,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                    ),
                  );
                }
                return SizedBox();
              }),

              const SizedBox(height: 10),

              // Time + Buttons Row
              Row(
                children: [
                  Text(
                    '@${note.username}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    formattedDateTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),

                  // Placeholder Buttons
                  IconButton(
                    onPressed: () {}, // Future Like Function
                    icon: Icon(Icons.favorite_border_rounded),
                    color: Colors.black54,
                  ),
                  IconButton(
                    onPressed: () {}, // Future Comment Function
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    color: Colors.black54,
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
