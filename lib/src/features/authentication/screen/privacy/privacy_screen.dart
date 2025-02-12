
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/changepass/change_pass.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.title});
  final String title;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreen();
}

class _PrivacyScreen extends State<PrivacyScreen> {




 @override
Widget build(BuildContext context) {
  return Scaffold(
   appBar: AppBar(title: Text(widget.title)),
    body: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [

                  _buildButton(context, "Change Password", ChangePass(title: 'Change Password',)),

                  _buildButtons(context, "Delete Account"),

          ],
        ),
      ),
    ),
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
          padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
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
  Widget _buildButtons(BuildContext context, String label) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: TextButton(
        onPressed: () {
          print("Navigating to: $label");
          
        },
        style: ButtonStyle(
          padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
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
