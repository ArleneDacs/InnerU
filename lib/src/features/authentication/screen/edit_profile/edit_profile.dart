import 'dart:async';
import 'dart:io';
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
  static const Duration _availabilityDebounce = Duration(milliseconds: 450);
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
  Timer? _usernameCheckDebounce;
  Timer? _emailCheckDebounce;

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
        final dynamic rawProfilePic = userData["profilePic"];
        final cleanedUrl = rawProfilePic is String ? rawProfilePic.trim() : "";
        _selectedImage = cleanedUrl.isEmpty ? null : cleanedUrl;
      });
      return userData;
    });
  }

  @override
  void dispose() {
    _usernameCheckDebounce?.cancel();
    _emailCheckDebounce?.cancel();
    _dobController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    try {
      final XFile? image =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;

      Uint8List bytes = await File(image.path).readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        print("Error decoding image.");
        return;
      }

      setState(() {
        _selectedImageTemp = image.path; // Temporarily store selected image
        _isButtonEnabled = true; // Enable update button
      });
    } catch (e) {
      print("Error picking image: $e");
    }
  }

  Future<String?> _uploadImage(Uint8List imageBytes) async {
    try {
      final fallbackName =
          '${AuthService.instance.currentUserId ?? 'profile'}.jpg';
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
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;

    setState(() {
      _isButtonEnabled = false; // Disable button while updating
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final newUsername = _usernameController.text.trim();

    try {
      Map<String, dynamic> updatedData = {
        "username": newUsername,
        "email": _emailController.text.trim(),
        "number": _phoneController.text.trim(),
      };

      if (_isBirthdateChanged) {
        updatedData["birthdate"] = _dobController.text.trim();
      }

      // If a new image is selected, upload it
      if (_selectedImageTemp != null) {
        if (!ImageStorageService.isConfigured) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "Image upload is not configured. Please sign in again."),
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

      final savedUser = await UserService.updateUserData(
        name: updatedData["username"] as String?,
        email: updatedData["email"] as String?,
        number: updatedData["number"] as String?,
        birthdate: updatedData["birthdate"] as String?,
      );
      final normalizedProfilePic =
          savedUser["profilePic"]?.toString() ?? updatedData["profilePic"];

      if (!mounted) return;
      setState(() {
        _selectedImage = normalizedProfilePic;
        _selectedImageTemp = null; // Clear temp image
      });

      Navigator.pop(context); // Close loading dialog

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

  void _scheduleUsernameAvailabilityCheck(String username) {
    _usernameCheckDebounce?.cancel();
    _usernameCheckDebounce = Timer(_availabilityDebounce, () {
      if (!mounted) return;
      unawaited(_checkUsernameAvailability(username));
    });
  }

  void _scheduleEmailAvailabilityCheck(String email) {
    _emailCheckDebounce?.cancel();
    _emailCheckDebounce = Timer(_availabilityDebounce, () {
      if (!mounted) return;
      unawaited(_checkEmailAvailability(email));
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
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

    if (!mounted) return;
    setState(() {
      _isUsernameValid = true;
      _isButtonEnabled = _usernameController.text.trim().isNotEmpty &&
          _emailController.text.trim().isNotEmpty &&
          _phoneController.text.trim().isNotEmpty &&
          _isUsernameValid &&
          _isEmailValid;
    });
  }

  bool _isEmailFormatValid(String email) {
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@gmail\.com$';
    RegExp regExp = RegExp(emailPattern);
    return regExp.hasMatch(email);
  }

  Future<void> _checkEmailAvailability(String email) async {
    if (email.isEmpty) {
      setState(() {
        _isEmailValid = false;
        _isButtonEnabled = false;
      });
      return;
    }

    if (!_isEmailFormatValid(email)) {
      setState(() {
        _isEmailValid = false;
        _isButtonEnabled = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isEmailValid = true;
      _isButtonEnabled = _usernameController.text.trim().isNotEmpty &&
          _emailController.text.trim().isNotEmpty &&
          _phoneController.text.trim().isNotEmpty &&
          _isUsernameValid &&
          _isEmailValid;
    });
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
                      _scheduleUsernameAvailabilityCheck(value.trim());
                    }),
                    _buildEditableInputField(
                        "Email", _emailController, companyTheme, (value) {
                      _scheduleEmailAvailabilityCheck(value.trim());
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
                              final navigator = Navigator.of(context);
                              setState(() {
                                _isButtonEnabled =
                                    false; // Disable button to prevent multiple taps
                              });

                              try {
                                await _updateUserData();
                                if (!mounted) return;
                                navigator.pushReplacement(
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
                _scheduleUsernameAvailabilityCheck(value.trim());
              } else if (label == "Email") {
                _scheduleEmailAvailabilityCheck(value.trim());
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
