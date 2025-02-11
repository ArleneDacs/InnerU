import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onPressed;
  const NoteCard({super.key, required this.note, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    DateTime displayTime = note.updatedAt.isAfter(note.createdAt)
        ? note.updatedAt
        : note.createdAt;

    String formattedDateTime =
        DateFormat('h:mma MMMM d, y').format(displayTime);
    return GestureDetector(
      onTap: onPressed,
      child: Card(
        elevation: 4,
        color: Color(note.color),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title,
                maxLines: 2,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    overflow: TextOverflow.ellipsis),
              ),
              Row(
                children: [
                  Container(),
                  Spacer(),
                  Text(
                    formattedDateTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color.fromARGB(255, 135, 135, 135),
                    ),
                  )
                ],
              ),
              SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Text(
                  note.note,
                  maxLines: 4,
                  style: TextStyle(
                    fontSize: 16,
                    overflow: TextOverflow.ellipsis,
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
