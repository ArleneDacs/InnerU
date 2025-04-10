import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_settings.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.title});
  final String title;

  @override
  State<EditProfile> createState() => MyEditProfileState();
}

class MyEditProfileState extends State<EditProfile> {
  String? _base64Image;
  String? _selectedImage;
  String? _selectedImageTemp;
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
      _selectedImage = userData["profilePic"] ?? null; // Use URL instead of base64
    });
    return userData;
  });

  
}
Future<void> pickImage() async {
  try {
    final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    Uint8List bytes = await File(image.path).readAsBytes();
    img.Image? originalImage = img.decodeImage(bytes);

    if (originalImage == null) {
      print("Error decoding image.");
      return;
    }

    img.Image resizedImage = img.copyResize(originalImage, width: 600, height: 600);
    Uint8List resizedBytes = Uint8List.fromList(img.encodeJpg(resizedImage));

    setState(() {
      _selectedImageTemp = image.path; // Temporarily store selected image
      _isButtonEnabled = true; // Enable update button
    });

  } catch (e) {
    print("Error picking image: $e");
  }
}

Future<String?> _uploadImageToFirebaseStorage(Uint8List imageBytes) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  try {
    Reference storageRef = FirebaseStorage.instance.ref().child("profile_pictures/${user.uid}.jpg");
    UploadTask uploadTask = storageRef.putData(imageBytes, SettableMetadata(contentType: "image/jpeg"));

    // Show loading animation while uploading
    TaskSnapshot snapshot = await uploadTask;
    String downloadUrl = await snapshot.ref.getDownloadURL();

    await FirebaseFirestore.instance.collection("users").doc(user.uid).update({
      "profilePic": downloadUrl,
    });

    print("Image uploaded successfully: $downloadUrl");
    return downloadUrl;
  } catch (e) {
    print("Error uploading image: $e");
    return null;
  }
}
Future<void> _updateUserData() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  setState(() {
    _isButtonEnabled = false; // Disable button while updating
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );
  });

DocumentSnapshot userDoc = await FirebaseFirestore.instance
    .collection("users")
    .doc(user.uid)
    .get();

String oldUsername = userDoc.get("username") ?? "";


  String newUsername = _usernameController.text.trim();

  Map<String, dynamic> updatedData = {
    "username": newUsername,
    "email": _emailController.text.trim(),
    "number": _phoneController.text.trim(),
  };

  if (_isBirthdateChanged) {
    updatedData["birthdate"] = _dobController.text.trim();
  }

  try {
    // If a new image is selected, upload it
    if (_selectedImageTemp != null) {
      Uint8List imageBytes = await File(_selectedImageTemp!).readAsBytes();
      String? downloadUrl = await _uploadImageToFirebaseStorage(imageBytes);

      if (downloadUrl != null) {
        updatedData["profilePic"] = downloadUrl;
      }
    }

    // Update user document
    await FirebaseFirestore.instance.collection("users").doc(user.uid).update(updatedData);

    // Update username in all userpoints documents for the user
QuerySnapshot pointsSnapshot = await FirebaseFirestore.instance
    .collection("userpoints")
    .where("username", isEqualTo: oldUsername)
    .get();

for (var doc in pointsSnapshot.docs) {
  await doc.reference.update({"username": newUsername});
}

    // Update username in all notes where the userId matches
    QuerySnapshot notesSnapshot = await FirebaseFirestore.instance
        .collection("notes")
        .where("userId", isEqualTo: user.uid)
        .get();

    for (var doc in notesSnapshot.docs) {
      await doc.reference.update({"username": newUsername});
    }

    // Update username in all comments for the given user
    QuerySnapshot allNotesSnapshot = await FirebaseFirestore.instance.collection("notes").get();

    for (var noteDoc in allNotesSnapshot.docs) {
      QuerySnapshot commentsSnapshot = await noteDoc.reference
          .collection("comments")
          .where("username", isEqualTo: user.displayName) // Assuming the user's display name was previously used
          .get();

      for (var commentDoc in commentsSnapshot.docs) {
        await commentDoc.reference.update({"username": newUsername});
      }
    }

    setState(() {
      _selectedImage = updatedData["profilePic"];
      _selectedImageTemp = null; // Clear temp image
    });

    Navigator.pop(context); // Close loading dialog

    // Redirect to the profile screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => ProfileSettings()),
    );

    print("User data updated successfully!");
  } catch (error) {
    Navigator.pop(context); // Close loading dialog if error occurs
    print("Error updating user data: $error");

    // Show error message
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Failed to update profile. Please try again."),
      backgroundColor: Colors.red,
    ));
  }
}




Future<void> _checkUsernameAvailability(String username) async {
  final user = FirebaseAuth.instance.currentUser;

  if (username.isEmpty) {
    setState(() {
      _isUsernameValid = false;
      _isButtonEnabled = false;
    });
    return;
  }

  if (username.length > 20) {
    setState(() {
      _isUsernameValid = false;
      _isButtonEnabled = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Username must be 20 characters or fewer."),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final querySnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('username', isEqualTo: username)
      .get();

  if (querySnapshot.docs.isNotEmpty && querySnapshot.docs.first.id != user?.uid) {
    setState(() {
      _isUsernameValid = false;
      _isButtonEnabled = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("This username is already taken."),
        backgroundColor: Colors.red,
      ),
    );
  } else {
    setState(() {
      _isUsernameValid = true;
      _isButtonEnabled = _usernameController.text.trim().isNotEmpty &&
                         _emailController.text.trim().isNotEmpty &&
                         _phoneController.text.trim().isNotEmpty &&
                         _isUsernameValid && _isEmailValid;
    });
  }
}




  bool _isEmailFormatValid(String email) {
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
    RegExp regExp = RegExp(emailPattern);
    return regExp.hasMatch(email);
  }
void _checkEmailAvailability(String email) async {
  if (email.isEmpty) {
    setState(() {
      _isEmailValid = false;
      _isButtonEnabled = false;
    });
    return;
  }

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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("This email is already linked to another account."),
      backgroundColor: Colors.red,
    ));
  } else {
    setState(() {
      _isEmailValid = true;
      _isButtonEnabled = _usernameController.text.trim().isNotEmpty &&
                         _emailController.text.trim().isNotEmpty &&
                         _phoneController.text.trim().isNotEmpty &&
                         _isUsernameValid && _isEmailValid;
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
                     _selectedImageTemp != null
  ? ClipOval(
      child: Image.file(
        File(_selectedImageTemp!), // Show selected image immediately
        width: MediaQuery.of(context).size.width * 0.35,
        height: MediaQuery.of(context).size.width * 0.35,
        fit: BoxFit.cover,
      ),
    )
  :  _selectedImage != null
  ? ClipOval(
      child: Image.network(
        _selectedImage!,
        width: MediaQuery.of(context).size.width * 0.35,
        height: MediaQuery.of(context).size.width * 0.35,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/avatar.png',
            width: MediaQuery.of(context).size.width * 0.35,
            height: MediaQuery.of(context).size.width * 0.35,
          );
        },
      ),
    )
  : Image.asset(
      'assets/images/avatar.png',
      width: MediaQuery.of(context).size.width * 0.35,
      height: MediaQuery.of(context).size.width * 0.35,
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
                _buildEditableInputField("Username", _usernameController, (value) {
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
  onPressed: _isButtonEnabled
      ? () async {
          setState(() {
            _isButtonEnabled = false; // Disable button to prevent multiple taps
          });

          try {
            await _updateUserData();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage(title: 'Profile')),
            );
          } catch (e) {
            print("Update failed: $e"); // Handle the error (e.g., show a Snackbar)
          } finally {
            setState(() {
              _isButtonEnabled = true; // Re-enable button
            });
          }
        }
      : null,
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
           maxLength: label == "Username" ? 20 : (label == "Phone Number" ? 11 : null),
            keyboardType: label == "Phone Number" ? TextInputType.number : TextInputType.text, // Set numeric keyboard
          inputFormatters: label == "Phone Number" ? [FilteringTextInputFormatter.digitsOnly] : [],// Prevent typing beyond 20 characters
          style: TextStyle(fontSize: 14, color: Colors.black),
          onChanged: (value) {
            if (label == "Username") {
              _checkUsernameAvailability(value.trim());
            } else if (label == "Email") {
              _checkEmailAvailability(value);
            } else {
              setState(() {
                _isButtonEnabled = _hasChanges();
              });
            }
            setState(() {
          _isButtonEnabled = _usernameController.text.trim().isNotEmpty &&
                            _emailController.text.trim().isNotEmpty &&
                            _phoneController.text.trim().isNotEmpty &&
                            _isUsernameValid && _isEmailValid;
        });
          },
          decoration: InputDecoration(
            counterText: label == "Username" ? null : "", // Style for counter
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
