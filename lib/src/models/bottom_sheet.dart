import 'package:flutter/material.dart';

class BottomSheetWidget {
  static void show(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Color(0xFF589675),
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ListTileTheme(
          iconColor: Colors.white,
          textColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.person),
                  title: Text("Profile"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/profile');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Icon(
                    Icons.star,
                    color: const Color(0xFFF3DDB3),
                  ),
                  title: Text("Leaderboard"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/leaderboard');
                  },
                ),
                Divider(),
                ListTile(
                  leading: Image.asset(
                    "assets/images/logout.png",
                    height: 25,
                  ),
                  title: Text("Log out"),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
