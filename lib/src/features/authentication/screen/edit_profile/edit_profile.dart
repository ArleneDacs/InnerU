import 'dart:convert';
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
  String? _selectedImage;
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _currentBirthdate = "";
  bool _isBirthdateChanged = false;
  bool _isUsernameValid = true;
  bool _isEmailValid = true;
  bool _isButtonEnabled = false;
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
        _base64Image = userData["profilePic"] ?? null;
      });
      return userData;
    });
  }

  Future<void> pickImage() async {
    try {
      final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null) {
        Uint8List bytes = await image.readAsBytes();
        img.Image? originalImage = img.decodeImage(Uint8List.fromList(bytes));

        if (originalImage != null) {
          img.Image resizedImage = img.copyResize(originalImage, width: 600, height: 600);
          Uint8List resizedBytes = Uint8List.fromList(img.encodeJpg(resizedImage));
          String base64String = base64Encode(resizedBytes);

          setState(() {
            _selectedImage = base64String;
            _isButtonEnabled = true;
          });
        }
      }
    } catch (e) {
      print("Error picking image: $e");
    }
  }

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

      if (_selectedImage != null) {
        updatedData["profilePic"] = _selectedImage;
      }

      await FirebaseFirestore.instance.collection("users").doc(user.uid).update(updatedData).then((_) {
        print("User data updated successfully!");
      }).catchError((error) {
        print("Error updating user data: $error");
      });
    }
  }

Future<void> _checkUsernameAvailability(String username) async {
  final user = FirebaseAuth.instance.currentUser;
  _isButtonEnabled = _isEmailValid && _isUsernameValid;

  if (user == null) return;

  final querySnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('username', isEqualTo: username)
      .get();

  if (querySnapshot.docs.isNotEmpty && querySnapshot.docs.first.id != user.uid) {
    setState(() {
      _isUsernameValid = false;
      _isButtonEnabled = false;
    });

    // Show a Snackbar with an error message for username
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("This username is already taken."),
      backgroundColor: Colors.red,
    ));
  } else {
    setState(() {
      _isUsernameValid = true;
      _isButtonEnabled = _isEmailValid && _isUsernameValid;
    });
  }
}


  bool _isEmailFormatValid(String email) {
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
    RegExp regExp = RegExp(emailPattern);
    return regExp.hasMatch(email);
  }
void _checkEmailAvailability(String email) async {
  _isButtonEnabled = _isEmailValid && _isUsernameValid;


  final user = FirebaseAuth.instance.currentUser;

  final querySnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: email)
      .get();

  if (querySnapshot.docs.isNotEmpty && querySnapshot.docs.first.id != user?.uid) {
    setState(() {
      _isEmailValid = false;
      _isButtonEnabled = false;
    });

    // Show a Snackbar with an error message for email
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("This email is already linked to another account."),
      backgroundColor: Colors.red,
    ));
  } else {
    setState(() {
      _isEmailValid = true;
      _isButtonEnabled = _isUsernameValid && _isEmailValid;
    });
  }
}




  @override
  Widget build(BuildContext context) {
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
            child: ListView(
              children: [
                SizedBox(height: 15),
                Center(
                  child: Stack(
                    children: [
                      _selectedImage != null
                          ? ClipOval(
                              child: Image.memory(
                                base64Decode(_selectedImage!),
                                width: MediaQuery.of(context).size.width * 0.35,
                                height: MediaQuery.of(context).size.width * 0.35,
                                fit: BoxFit.cover,
                              ),
                            )
                          : _base64Image == null
                              ? Image.asset(
                                  'assets/images/avatar.png',
                                  width: MediaQuery.of(context).size.width * 0.35,
                                  height: MediaQuery.of(context).size.width * 0.35,
                                )
                              : ClipOval(
                                  child: Image.memory(
                                    base64Decode(_base64Image!),
                                    width: MediaQuery.of(context).size.width * 0.35,
                                    height: MediaQuery.of(context).size.width * 0.35,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                      Positioned(
                        bottom: 0,
                        right: 10,
                        child: GestureDetector(
                          onTap: pickImage,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.black,
                            child: Icon(Icons.edit, size: 25, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                _buildEditableInputField("Name", _usernameController, (value) {
                  if (value != _usernameController.text) {
                    _checkUsernameAvailability(value);
                  }
                }),
                _buildEditableInputField("Email", _emailController, (value) {
                  setState(() {
                    _isEmailValid = _isEmailFormatValid(value) && value != _emailController.text.trim();
                    _isButtonEnabled = _isEmailValid && _isUsernameValid;
                  });
                }),
                _buildEditableInputField("Phone Number", _phoneController, (value) {
                  _isButtonEnabled = _hasChanges();
                }),
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
                        _isButtonEnabled = _hasChanges(); // Enable button if any changes
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
                SizedBox(height: 30.0),
              ElevatedButton(
                onPressed: _isButtonEnabled ? () async {
                  await _updateUserData();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => ProfilePage(title: 'Profile')),
                  );
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isButtonEnabled ? Color(0xFFce8f5a) : Colors.grey,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                ),
                child: Text(
                  'Update',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),

              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditableInputField(String label, TextEditingController controller, Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          SizedBox(height: 5),
          TextField(
            controller: controller,
            style: TextStyle(fontSize: 14, color: Colors.black),
            onChanged: (value) {
              onChanged(value);
              if (label == "Name") {
                _checkUsernameAvailability(value);
              } else if (label == "Email") {
                _checkEmailAvailability(value);
              } else {
                setState(() {
                  _isButtonEnabled = _hasChanges();
                });
              }
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: Color(0xFFffecc9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

 bool _hasChanges() {
  return _usernameController.text.trim() != _currentBirthdate ||
      _emailController.text.trim() != _currentBirthdate ||
      _dobController.text.trim().isNotEmpty;
}

}
