import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';

class NotesType extends StatefulWidget {
  const NotesType({super.key});

  @override
  State<NotesType> createState() => _NotesTypeState();
}

class _NotesTypeState extends State<NotesType> {
  String username = "Getting username...";
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    UserService.getUserData().then((data) => setState(() {
          username = data["username"]!;
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Journal Entry"),
        ),
        body: Column(
          children: [Text(username)],
        ));
  }
}
