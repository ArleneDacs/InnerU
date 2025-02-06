import 'package:flutter/material.dart';

class Notes extends StatefulWidget {
  const Notes({super.key});

  @override
  State<Notes> createState() => _NotesState();
}

class _NotesState extends State<Notes> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          margin: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image(image: AssetImage('assets/images/Diary-bro (1).png')),
              Center(
                child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, 'notesType');
                    },
                    child: Text("Write")),
              ),
              Center(
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(context, 'noteGallery');
                  },
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      "SHOW NOTES.",
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
