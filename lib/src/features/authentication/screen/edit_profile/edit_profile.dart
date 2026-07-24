import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key, required this.title});
  final String title;

  @override
  State<EditProfile> createState() => MyEditProfileState();
}

class MyEditProfileState extends State<EditProfile> {
  String? _oldUsername;
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
        _oldUsername = userData["username"];
        _usernameController.text = userData["username"] ?? "";
        _emailController.text = userData["email"] ?? "";
        _phoneController.text = userData["number"] ?? "";
        _currentBirthdate = userData["birthdate"] ?? "";
        _dobController.text = _currentBirthdate;
        final dynamic rawProfilePic = userData["profilePic"];
        final cleanedUrl = rawProfilePic is String ? rawProfilePic.trim() : "";
        _selectedImage = cleanedUrl.isEmpty ? null : cleanedUrl;
      });
      return userData;
    });
  }

  Future<void> pickImage() async {
    try {
      final XFile? image =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;

      Uint8List bytes = await File(image.path).readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Couldn't read that photo. Please try a different one."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _selectedImageTemp = image.path; // Temporarily store selected image
        _isButtonEnabled = true; // Enable update button
      });
    } catch (e) {
      print("Error picking image: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't load that photo. Please try a different one."),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _uploadImage(Uint8List imageBytes) async {
    try {
      final fallbackName =
          AuthService.instance.currentSession?.id.toString() ?? 'profile.jpg';
      final imageUrl = await ImageStorageService.uploadImageBytes(
        imageBytes,
        fileName: fallbackName,
      );
      if (imageUrl != null) {
        print("Image uploaded successfully: $imageUrl");
      }
      return imageUrl;
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  Future<void> _updateUserData() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final userId = session.id.toString();

    setState(() {
      _isButtonEnabled = false; // Disable button while updating
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );
    });

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
        if (!ImageStorageService.isConfigured) {
          if (!mounted) return;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "Image upload is not configured. Set cloudName/uploadPreset in lib/src/config/cloudinary_config.dart."),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isButtonEnabled = true;
          });
          return;
        }

        Uint8List imageBytes = await File(_selectedImageTemp!).readAsBytes();
        String? downloadUrl = await _uploadImage(imageBytes);

        if (downloadUrl != null) {
          updatedData["profilePic"] = downloadUrl;
        } else {
          if (!mounted) return;
          Navigator.pop(context);
          final reason = ImageStorageService.lastError;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason == null || reason.isEmpty
                  ? "Profile image upload failed. Please try again."
                  : "Profile image upload failed: $reason"),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isButtonEnabled = true;
          });
          return;
        }
      }

      // Update the user profile through the API. UserService.getUserData()
      // (which every screen, including this one, reads profile data from)
      // reads from /api/me, not Firestore -- writing to the Firestore
      // "users" collection here was a no-op from the user's perspective,
      // since nothing ever read profile fields back from it.
      await UserService.updateUserFields({
        'name': newUsername,
        'email': _emailController.text.trim(),
        'number': _phoneController.text.trim(),
        if (_isBirthdateChanged) 'birthdate': _dobController.text.trim(),
        if (updatedData['profilePic'] != null)
          'profile_pic': updatedData['profilePic'],
      });

      // Update username in all notes owned by this user (batched: one
      // round trip instead of one per note).
      QuerySnapshot notesSnapshot = await FirebaseFirestore.instance
          .collection("notes")
          .where("userId", isEqualTo: userId)
          .get();

      if (notesSnapshot.docs.isNotEmpty) {
        final notesBatch = FirebaseFirestore.instance.batch();
        for (var doc in notesSnapshot.docs) {
          notesBatch.update(doc.reference, {"username": newUsername});
        }
        await notesBatch.commit();
      }

      // Update username on every comment this user left, across all notes.
      // (This used to also run an equivalent username-matched pass here
      // before calling updateUsernameInComments below -- two full scans of
      // every note in the app, each doing a sequential per-note comments
      // query, which is what made profile saves take minutes. The userId
      // match below is the reliable one (userId is immutable; matching by
      // the old display name could miss or mismatch comments), so the
      // duplicate pass was removed rather than fixed.
      await updateUsernameInComments(userId, newUsername);

      if (_oldUsername != null && _oldUsername != newUsername) {
        QuerySnapshot userPointsSnapshot = await FirebaseFirestore.instance
            .collection("userpoints")
            .where("username", isEqualTo: _oldUsername)
            .get();

        if (userPointsSnapshot.docs.isNotEmpty) {
          final pointsBatch = FirebaseFirestore.instance.batch();
          for (var doc in userPointsSnapshot.docs) {
            pointsBatch.update(doc.reference, {"username": newUsername});
          }
          await pointsBatch.commit();
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedImage = updatedData["profilePic"];
        _selectedImageTemp = null; // Clear temp image
      });

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Navigation from here is the caller's responsibility (see the
      // "Update" button's onPressed) -- this method used to also
      // pushReplacement to ProfileSettings here, which meant every save
      // fired two competing pushReplacement transitions back to back, the
      // second one using a context whose route the first had already
      // replaced. That left the destination screen stuck mid-render
      // (including the just-uploaded profile picture) until something
      // external, like backgrounding the app, forced a full repaint.
      print("User data updated successfully!");
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog if error occurs
      print("Error updating user data: $error");

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Failed to update profile. Please try again."),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> updateUsernameInComments(
      String userId, String newUsername) async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    QuerySnapshot notesSnapshot = await firestore.collection('notes').get();

    // One comments query per note, but fired concurrently instead of
    // awaited one at a time -- with hundreds of notes in the app, doing
    // this sequentially was the actual reason profile saves took minutes
    // (this scan runs across every note in the app, not just this user's).
    final commentsSnapshots = await Future.wait(
      notesSnapshot.docs.map(
        (noteDoc) => noteDoc.reference
            .collection('comments')
            .where('userId', isEqualTo: userId)
            .get(),
      ),
    );

    final matchingComments = commentsSnapshots
        .expand((snapshot) => snapshot.docs)
        .toList();
    if (matchingComments.isEmpty) return;

    // Firestore batched writes cap at 500 operations, so chunk defensively.
    for (var i = 0; i < matchingComments.length; i += 500) {
      final chunk = matchingComments.skip(i).take(500);
      final batch = firestore.batch();
      for (final commentDoc in chunk) {
        batch.update(commentDoc.reference, {'username': newUsername});
      }
      await batch.commit();
    }
  }

  Future<void> _checkUsernameAvailability(String username) async {
    final currentUserId = AuthService.instance.currentSession?.id.toString();

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

    if (!mounted) return;
    if (querySnapshot.docs.isNotEmpty &&
        querySnapshot.docs.first.id != currentUserId) {
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
            _isUsernameValid &&
            _isEmailValid;
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

    final currentUserId = AuthService.instance.currentSession?.id.toString();

    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (!mounted) return;
    if (querySnapshot.docs.isNotEmpty &&
        querySnapshot.docs.first.id != currentUserId) {
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
            _isUsernameValid &&
            _isEmailValid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor:
                companyTheme.isDark ? companyTheme.surfaceColor : null,
            foregroundColor: companyTheme.isDark ? companyTheme.inkColor : null,
            surfaceTintColor: Colors.transparent,
            title: Text(widget.title),
          ),
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
                                    File(
                                        _selectedImageTemp!), // Show selected image immediately
                                    width: MediaQuery.of(context).size.width *
                                        0.35,
                                    height: MediaQuery.of(context).size.width *
                                        0.35,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : (_selectedImage != null &&
                                      _selectedImage!.trim().isNotEmpty)
                                  ? ClipOval(
                                      child: Image.network(
                                        _selectedImage!,
                                        width:
                                            MediaQuery.of(context).size.width *
                                                0.35,
                                        height:
                                            MediaQuery.of(context).size.width *
                                                0.35,
                                        fit: BoxFit.cover,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Center(
                                              child:
                                                  CircularProgressIndicator());
                                        },
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return Image.asset(
                                            'assets/images/avatar.png',
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.35,
                                            height: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.35,
                                          );
                                        },
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/images/avatar.png',
                                      width: MediaQuery.of(context).size.width *
                                          0.35,
                                      height:
                                          MediaQuery.of(context).size.width *
                                              0.35,
                                    ),
                          Positioned(
                            bottom: 0,
                            right: 10,
                            child: GestureDetector(
                              onTap: pickImage,
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF3E9189),
                                child: Icon(Icons.edit,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 40),
                    _buildEditableInputField(
                        "Username", _usernameController, companyTheme, (value) {
                      if (value != _usernameController.text) {
                        _checkUsernameAvailability(value);
                      }
                    }),
                    _buildEditableInputField(
                        "Email", _emailController, companyTheme, (value) {
                      setState(() {
                        _isEmailValid = _isEmailFormatValid(value) &&
                            value != _emailController.text.trim();
                        _isButtonEnabled = _isEmailValid && _isUsernameValid;
                      });
                    }),
                    _buildEditableInputField(
                        "Phone Number", _phoneController, companyTheme,
                        (value) {
                      _isButtonEnabled = _hasChanges();
                    }),
                    Container(
                      margin: EdgeInsets.only(left: 20),
                      child: Row(
                        children: [
                          Text(
                            'Date of Birth',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: companyTheme.inkColor,
                            ),
                          ),
                          SizedBox(width: 15),
                          if (_dobController.text.trim().isEmpty)
                            Image.asset('assets/images/alert.png',
                                width: 24, height: 24),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20, top: 10, right: 12, bottom: 10),
                      child: TextField(
                        controller: _dobController,
                        readOnly: true,
                        onTap: () async {
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _dobController.text.isNotEmpty
                                ? DateFormat('MMMM dd, yyyy')
                                    .parse(_dobController.text)
                                : DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2101),
                          );
                          if (picked != null) {
                            setState(() {
                              _dobController.text =
                                  DateFormat('MMMM dd, yyyy').format(picked);
                              _isBirthdateChanged =
                                  true; // Mark birthdate as changed
                              _isButtonEnabled =
                                  _hasChanges(); // Enable button if any changes
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _dobController.text.isNotEmpty
                              ? _dobController.text
                              : "Enter your birthdate",
                          filled: true,
                          fillColor: companyTheme.isDark
                              ? companyTheme.surfaceColor
                              : Colors.white,
                          suffixIcon: const Icon(Icons.calendar_today_outlined,
                              size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: companyTheme.isDark
                                ? BorderSide(
                                    color: companyTheme.primaryColor
                                        .withValues(alpha: 0.2),
                                  )
                                : const BorderSide(color: Color(0xFFE3EAE8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: companyTheme.isDark
                                ? BorderSide(
                                    color: companyTheme.primaryColor
                                        .withValues(alpha: 0.2),
                                  )
                                : const BorderSide(color: Color(0xFFE3EAE8)),
                          ),
                        ),
                        style: TextStyle(color: companyTheme.inkColor),
                      ),
                    ),
                    SizedBox(height: 30.0),
                    ElevatedButton(
                      onPressed: _isButtonEnabled
                          ? () async {
                              setState(() {
                                _isButtonEnabled =
                                    false; // Disable button to prevent multiple taps
                              });

                              try {
                                await _updateUserData();
                                if (!context.mounted) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          ProfilePage(title: 'Profile')),
                                );
                              } catch (e) {
                                print(
                                    "Update failed: $e"); // Handle the error (e.g., show a Snackbar)
                              } finally {
                                if (mounted) {
                                  setState(() {
                                    _isButtonEnabled =
                                        true; // Re-enable button
                                  });
                                }
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isButtonEnabled
                            ? companyTheme.primaryColor
                            : Colors.grey,
                        elevation: 0,
                        padding:
                            EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                      ),
                      child: Text(
                        'Update',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEditableInputField(
    String label,
    TextEditingController controller,
    CompanyThemeData companyTheme,
    Function(String) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: companyTheme.inkColor,
            ),
          ),
          SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLength: label == "Username"
                ? 20
                : (label == "Phone Number" ? 11 : null),
            keyboardType: label == "Phone Number"
                ? TextInputType.number
                : TextInputType.text, // Set numeric keyboard
            inputFormatters: label == "Phone Number"
                ? [FilteringTextInputFormatter.digitsOnly]
                : [], // Prevent typing beyond 20 characters
            style: TextStyle(fontSize: 14, color: companyTheme.inkColor),
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
                    _isUsernameValid &&
                    _isEmailValid;
              });
            },
            decoration: InputDecoration(
              counterText: label == "Username" ? null : "", // Style for counter
              filled: true,
              fillColor: companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: companyTheme.isDark
                    ? BorderSide(
                        color: companyTheme.primaryColor.withValues(alpha: 0.2),
                      )
                    : const BorderSide(color: Color(0xFFE3EAE8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: companyTheme.isDark
                    ? BorderSide(
                        color: companyTheme.primaryColor.withValues(alpha: 0.2),
                      )
                    : const BorderSide(color: Color(0xFFE3EAE8)),
              ),
              contentPadding: EdgeInsets.all(14),
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
