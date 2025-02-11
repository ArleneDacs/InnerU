import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NotesType extends StatefulWidget {
  final Note note;
  const NotesType({super.key, required this.note});

  @override
  State<NotesType> createState() => _NotesTypeState();
}

class _NotesTypeState extends State<NotesType> {
  final CollectionReference myNotes =
      FirebaseFirestore.instance.collection('notes');

  String username = "Loading...";
  late Note note;
  String titleString = '';
  String noteString = '';
  late int color;

  late TextEditingController titleController;
  late TextEditingController contentController;

  @override
  void initState() {
    super.initState();
    note = widget.note;
    titleString = note.title;
    noteString = note.note;
    color = note.color == 0xFFFFFFFF ? generateRandomLightShade() : note.color;
    titleController = TextEditingController(text: titleString);
    contentController = TextEditingController(text: noteString);

    UserService.getUserData().then((data) => setState(() {
          username = data["username"]!;
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              saveNotes();
              Navigator.pop(context);
            },
            icon: Icon(Icons.arrow_back)),
        actions: <Widget>[
          IconButton(
              onPressed: () {
                saveNotes();
              },
              icon: Icon(Icons.save)),
          if (note.id.isNotEmpty)
            IconButton(
                onPressed: () {
                  myNotes.doc(note.id).delete();
                  Navigator.pop(context);
                },
                icon: Icon(Icons.delete))
        ],
      ),
      body: SafeArea(
          child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              controller: titleController,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Title",
              ),
              onChanged: (value) {
                titleString = value;
              },
            ),
            Expanded(
              child: TextField(
                controller: contentController,
                maxLines: null,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "Start typing...",
                ),
                onChanged: (value) {
                  noteString = value;
                },
              ),
            )
          ],
        ),
      )),
    );
  }

  void saveNotes() async {
    DateTime now = DateTime.now();
    if (note.id.isEmpty) {
      await myNotes.add({
        'username': username,
        'title': titleString,
        'note': noteString,
        'color': color,
        'createdAt': now
      });
    } else {
      await myNotes.doc(note.id).update({
        'username': username,
        'title': titleString,
        'note': noteString,
        'color': color,
        'updatedAt': now
      });
    }
  }
}
