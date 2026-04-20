import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/edit_profile/edit_profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/privacy/privacy_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_goal_screen.dart';
import 'package:selfcare_projects/src/features/meditation_song/meditation_song.dart';

class ProfileSettings extends StatelessWidget {
  const ProfileSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Profile Settings",
                style: TextStyle(fontSize: 35),
              ),
              SizedBox(height: 70),
              _buildSectionTitle("General"),
              _buildButton(
                  context,
                  "Edit Profile",
                  EditProfile(
                    title: 'Edit Profile',
                  )),
              _buildButton(
                context,
                "Step Goal",
                StepGoalScreen(),
              ),
              _buildSectionTitle("Audio Settings"),
              _buildButton(context, "Change Meditation Song", MeditationSong()),
              _buildSectionTitle("Account Settings"),
              _buildButton(
                  context,
                  "Privacy",
                  PrivacyScreen(
                    title: 'Privacy',
                  )),
              SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      alignment: Alignment.centerLeft,
      margin: EdgeInsets.only(top: 10, bottom: 10),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
          color: Color(0xFFF3DDB3), borderRadius: BorderRadius.circular(5)),
      child: Text(title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  // Button Widget with Navigation
  Widget _buildButton(BuildContext context, String label, Widget targetScreen) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: TextButton(
        onPressed: () {
          print("Navigating to: $label");
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        },
        style: ButtonStyle(
          padding: MaterialStateProperty.all(
              EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
          overlayColor: MaterialStateProperty.all(Colors.grey.shade200),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 17, color: Colors.black)),
            Icon(Icons.arrow_forward_ios, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
