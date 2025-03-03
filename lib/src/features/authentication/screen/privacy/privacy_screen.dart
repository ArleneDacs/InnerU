import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/changepass/change_pass.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.title});
  final String title;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreen();
}

class _PrivacyScreen extends State<PrivacyScreen> {
  TextEditingController verificationController = TextEditingController();
  TextEditingController passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              _buildButtons(context, "Delete Account"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, String label, Widget targetScreen) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      width: double.infinity,
      child: TextButton(
        onPressed: () {
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
          openDelete();
        },
        style: ButtonStyle(
          padding: MaterialStateProperty.all(EdgeInsets.symmetric(vertical: 15, horizontal: 20)),
          overlayColor: MaterialStateProperty.all(Colors.grey.shade200),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 17, color: Colors.black)),
            SizedBox(width: 10),
            Image.asset(
              "assets/images/reminder.png",
              height: 25,
              width: 25,
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Future openDelete() => showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            'Are you sure you want to delete your account?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
           content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
          child: Text(
            '⚠️ This is extremely important!',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold,fontStyle: FontStyle.italic),
            textAlign: TextAlign.center, 
          ),
        ),
      SizedBox(height: 30),
          Text(
            'You will no longer be billed, and after 90 days, your username will be available to anyone on SelfCare.',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          SizedBox(height: 10),
        Text.rich(
  TextSpan(
    children: [
      TextSpan(
        text: 'To verify, type ',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      TextSpan(
        text: 'delete account', // This part is italic
        style: TextStyle(
          color: Colors.white,
          fontStyle: FontStyle.italic, // Italic text
          fontSize: 14,
        ),
      ),
      TextSpan(
        text: ' below:',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    ],
  ),
),

          
          SizedBox(height: 10),
          SizedBox(
  height: 40, // Adjust height as needed
  child: TextField(
    controller: passwordController,
    obscureText: true,
    style: TextStyle(color: Colors.white70, fontSize: 14), // Smaller text
    decoration: InputDecoration(
      labelStyle: TextStyle(color: Colors.white70),
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12), // Reduce padding
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white, width: 2.0),
      ),
    ),
  ),
),
            SizedBox(height: 10),
          Text(
            'Confirm Password:',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          SizedBox(height: 10),
      SizedBox(
  height: 40, // Adjust height as needed
  child: TextField(
    controller: passwordController,
    obscureText: true,
    style: TextStyle(color: Colors.white70, fontSize: 14), // Smaller text
    decoration: InputDecoration(
      labelStyle: TextStyle(color: Colors.white70),
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12), // Reduce padding
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white, width: 2.0),
      ),
    ),
  ),
),

        ],
      ),
        actions: [
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, // Pushes buttons to opposite sides
    children: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(
          'Cancel',
          style: TextStyle(color: Colors.white),
        ),
      ),
      TextButton(
        onPressed: deleteAccount,
        child: Text(
          'Delete this account',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  ),
],

        ),
      );

  void deleteAccount() {
    if (verificationController.text.toLowerCase() == "delete account" &&
        passwordController.text.isNotEmpty) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Account deletion process initiated."),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Verification or password incorrect."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
