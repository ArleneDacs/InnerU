import 'dart:convert'; // For base64 encoding/decoding
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img; 
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.title});
  final String title;

  @override
  State<EditProfile> createState() => MyEditProfileState();
}

class MyEditProfileState extends State<EditProfile> {
  String? _base64Image;
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _currentBirthdate = "";
  bool _isBirthdateChanged = false; // Track if birthdate has changed
  Future<Map<String, dynamic>>? _userDataFuture;

  @override
  void initState() {
    super.initState();
    _userDataFuture = UserService.getUserData().then((userData) {
      setState(() {
        _usernameController.text = userData["username"] ?? "";
        _emailController.text = userData["email"] ?? "";
        _phoneController.text = userData["number"] ?? "";
        _currentBirthdate = userData["birthdate"] ?? "";
        _dobController.text = _currentBirthdate;
        _base64Image = userData["profilePic"] ?? null; // Fetch base64 image string
      });
      return userData;
    });
  }

  Future<void> pickImage() async {
  try {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null) {
      // Load image and resize it
      Uint8List bytes = await image.readAsBytes();
      img.Image? originalImage = img.decodeImage(Uint8List.fromList(bytes));

      if (originalImage != null) {
        // Resize the image to a smaller size (e.g., 600x600)
        img.Image resizedImage = img.copyResize(originalImage, width: 600, height: 600);
        // Convert the resized image back to bytes
        Uint8List resizedBytes = Uint8List.fromList(img.encodeJpg(resizedImage));
        String base64String = base64Encode(resizedBytes);

        setState(() {
          _base64Image = base64String;
        });

        // Update the profile picture in Firestore
        await _updateUserData();
      }
    }
  } catch (e) {
    print("Error picking image: $e");
  }
}

  // Update user data including the profilePic (base64 string)
  Future<void> _updateUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      Map<String, dynamic> updatedData = {
        "username": _usernameController.text.trim(),
        "email": _emailController.text.trim(),
        "number": _phoneController.text.trim(),
      };

      if (_isBirthdateChanged) {
        updatedData["birthdate"] = _dobController.text.trim();
      }

      if (_base64Image != null) {
        updatedData["profilePic"] = _base64Image; // Store the base64 image string
      }

      print("Updated data: $updatedData");

      await FirebaseFirestore.instance.collection("users").doc(user.uid).update(updatedData).then((_) {
        print("User data updated successfully!");
      }).catchError((error) {
        print("Error updating user data: $error");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _userDataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(height: 15),
                Stack(
                  children: [
                    _base64Image == null
                        ? Image.asset(
                            'assets/images/avatar.png', // Default image if no profilePic is available
                            width: 150,
                            height: 150,
                          )
                        : ClipOval(
                            child: Image.memory(
                              base64Decode(_base64Image!), // Decode base64 string to image
                              width: 150,
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                    Positioned(
                      bottom: 0,
                      right: 10,
                      child: GestureDetector(
                        onTap: pickImage, // Allow user to pick a new image
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.black,
                          child: Icon(Icons.edit, size: 25, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 40),
                _buildEditableInputField("Name", _usernameController),
                _buildEditableInputField("Email", _emailController),
                _buildEditableInputField("Phone Number", _phoneController),
                Container(
                  margin: EdgeInsets.only(left: 20),
                  child: Row(
                    children: [
                      Text(
                        'Date of Birth',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(width: 15),
                      if (_dobController.text.trim().isEmpty)
                        Image.asset('assets/images/alert.png', width: 24, height: 24),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 10, right: 12, bottom: 10),
                  child: TextField(
                    controller: _dobController,
                    readOnly: true,
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: _dobController.text.isNotEmpty
                            ? DateFormat('MMMM dd, yyyy').parse(_dobController.text)
                            : DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2101),
                      );
                      if (picked != null) {
                        setState(() {
                          _dobController.text = DateFormat('MMMM dd, yyyy').format(picked);
                          _isBirthdateChanged = true; // Mark birthdate as changed
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _dobController.text.isNotEmpty ? _dobController.text : "Enter your birthdate",
                      filled: true,
                      fillColor: Color(0xFFffecc9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: EdgeInsets.only(top: 35.0),
                  child: ElevatedButton(
                    onPressed: () async {
                      await _updateUserData();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => ProfilePage(title: 'Profile')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFce8f5a),
                      elevation: 0,
                      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
                    ),
                    child: Text(
                      'Update',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Editable Input Field
  Widget _buildEditableInputField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 5),
          TextField(
            controller: controller,
            style: TextStyle(fontSize: 14, color: Colors.black),
            decoration: InputDecoration(
              filled: true,
              fillColor: Color(0xFFffecc9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
