import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CommunityBottomSheet {
  static void show(BuildContext context) {
    showModalBottomSheet(
        backgroundColor: Color(0xFFCE8F5A),
        context: context,
        builder: (context) {
          return ListTileTheme(
            iconColor: Color(0xFFFFFFFF),
            textColor: Color(0xFFFFFFFF),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                      leading: Icon(Icons.settings),
                      title: Text("Profile Settings"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/profileSettings');
                      }),
                  Divider(),
                  ListTile(
                      leading: Icon(Icons.note),
                      title: Text("Write"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, 'notesType');
                      }),
                  Divider(),
                  ListTile(
                      leading: Icon(Icons.list),
                      title: Text("View Other User Progress"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/userprogress');
                      }),
                ],
              ),
            ),
          );
        });
  }
}
