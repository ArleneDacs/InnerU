import 'dart:io';
import 'dart:convert'; // Add this for Base64 encoding

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/models/customSnackbar.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NotesType extends StatefulWidget {
  final Note note;
  final String? postId; // Nullable
  const NotesType({super.key, required this.note, this.postId});

  @override
  State<NotesType> createState() => _NotesTypeState();
}

class _NotesTypeState extends State<NotesType> {
  String? selectedCategory;
  List<Widget> contentWidgets = []; // This will store text and image widgets
  final ImagePicker _picker = ImagePicker();
  List<String> uploadedImageUrls = [];
  List<String> imagePaths = [];
  XFile? _selectedImage;

  final CollectionReference myNotes =
      FirebaseFirestore.instance.collection('notes');

  String username = "Loading...";
  late Note note;
  String titleString = '';
  late List<dynamic> noteString;
  late int color;
  bool _isSaving = false;
  bool _mounted = true;
  late SnackBar alertContent;

  late TextEditingController titleController;
  late TextEditingController contentController = TextEditingController();

  get todayTasks => null;

  @override
  void initState() {
    super.initState();
    note = widget.note;
    titleString = note.title;
    color = note.color == 0xFFFFFFFF ? generateRandomLightShade() : note.color;
    titleController = TextEditingController(text: titleString);

    if (note.note.isEmpty) {
      contentWidgets.add(
        TextField(
          controller: TextEditingController(),
          maxLines: null,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: "Start typing your note here...",
          ),
          onSubmitted: (value) {
            addText(value);
          },
        ),
      );
    } else {
      for (var item in note.note) {
        if (item["type"] == "text") {
          contentController = TextEditingController(text: item["value"]);
          contentWidgets.add(
            TextField(
              controller: contentController,
              maxLines: null,
              decoration: InputDecoration(border: InputBorder.none),
              onSubmitted: (value) {
                addText(value);
              },
            ),
          );
        } else if (item["type"] == "image") {
          contentWidgets.add(
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Image.network(
                  item["value"]!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                        child: CircularProgressIndicator()); // Show loader
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Text("Image failed to load",
                        style: TextStyle(color: Colors.red));
                  },
                )),
          );
        }
      }
    }

    UserService.getUserData().then((data) {
      setState(() {
        username = data["username"]!;
      });
    });
  }

  @override
  void dispose() {
    _isSaving = false; // Mark the widget as unmounted when disposed
    super.dispose();
  }

  bool _isFormValid = false;

  void _validateForm() {
    bool hasTitle = titleController.text.trim().isNotEmpty;
    bool hasText = contentWidgets.any((widget) =>
        widget is TextField &&
        (widget.controller?.text.trim().isNotEmpty ?? false));
    bool hasImage = uploadedImageUrls.isNotEmpty;
    bool hasCategory =
        selectedCategory != null && selectedCategory!.trim().isNotEmpty;

    bool isValid = false;

    if (selectedCategory == "Learning") {
      // Image is optional
      isValid = hasTitle && hasText && hasCategory;
    } else if (selectedCategory == "Add Value") {
      // Image is required
      isValid = hasTitle && hasText && hasImage && hasCategory;
    }

    setState(() {
      _isFormValid = isValid;
    });
  }

  Future<bool> _showExitConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Discard changes?'),
            content: Text('Are you sure you want to leave without saving?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Yes'),
              ),
            ],
          ),
        ) ??
        false; // Return false if dialog is dismissed without selection
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          bool shouldLeave = await _showExitConfirmationDialog();
          return shouldLeave;
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () async {
                bool shouldLeave = await _showExitConfirmationDialog();
                if (shouldLeave) {
                  Navigator.pop(context);
                }
              },
              icon: Icon(Icons.arrow_back),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: _isFormValid
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text("Save this note?"),
                            content: Text(
                                "Do you want to save this note for later?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () {
                                  saveNotes(isSaved: true);
                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                },
                                child: Text("Save",
                                    style: TextStyle(color: Colors.blue)),
                              ),
                            ],
                          ),
                        );
                      }
                    : null, // Disabled when _isFormValid is false
                child: Text("Save",
                    style: TextStyle(
                        fontSize: 15,
                        color: _isFormValid ? Colors.black : Colors.grey)),
              ),
              TextButton(
                onPressed: _isFormValid
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text("Post this note?"),
                            content: Text(
                                "Are you sure you want to share this note?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () {
                                  saveNotes(isSaved: false);

                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                },
                                child: Text("Yes",
                                    style: TextStyle(color: Colors.green)),
                              ),
                            ],
                          ),
                        );
                      }
                    : null, // Disabled when _isFormValid is false
                child: Text("Post",
                    style: TextStyle(
                        fontSize: 15,
                        color: _isFormValid ? Colors.black : Colors.grey)),
              ),
            ],
          ),
          body: SafeArea(
              child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  color: Colors.grey.shade100,
                  child: DropdownButton<String>(
                    value: selectedCategory,
                    hint: Text("Select Category"),
                    isExpanded: true, // Makes it full-width
                    items: ["Add Value", "Learning"].map((String category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedCategory = newValue;
                      });
                      _validateForm();
                    },
                  ),
                ),
                SizedBox(
                  height: 20,
                ),

                TextField(
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  controller: titleController,
                  maxLength: 40,
                  onChanged: (value) => _validateForm(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: "Title",
                  ),
                ),

                Expanded(
                  child: ListView(
                    children: [
                      ...contentWidgets.map((widget) {
                        if (widget is TextField) {
                          return TextField(
                            controller: widget.controller,
                            onChanged: (value) => _validateForm(),
                            decoration: widget.decoration,
                          );
                        }
                        return widget;
                      }),
                      buildImageSlider(),
                      SizedBox(height: 10),
                    ],
                  ),
                ),

                // Button for Adding Images
                ElevatedButton(
                  onPressed: pickImage,
                  child: Icon(Icons.image_search, size: 30),
                ),
              ],
            ),
          )),
        ));
  }

  Future<void> _saveDailyActivity({
    bool meditation = false,
    bool steps = false,
    bool learning = false,
    bool addValue = false,
  }) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    FirebaseFirestore firestore = FirebaseFirestore.instance;

    // Fetch username from Firestore user document
    DocumentSnapshot userDoc =
        await firestore.collection('users').doc(userId).get();
    String? username = userDoc.exists ? userDoc.get('username') : null;

    if (username != null) {
      String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Use UID for document ID
      DocumentReference docRef =
          firestore.collection('dailytracker').doc('$userId-$formattedDate');

      // Use Firestore's FieldValue.merge to update without overwriting other fields
      await docRef.set({
        'userId': userId,
        'username': username,
        'date': formattedDate,
        if (meditation) 'meditation': true,
        if (steps) 'steps': true,
        if (learning) 'learning': true,
        if (addValue) 'addValue': true,
      }, SetOptions(merge: true));

      print(
          "Updated Firestore: meditation=$meditation, steps=$steps, learning=$learning, addValue=$addValue for userId: $userId, username: $username");
    } else {
      print("Error: Username not found for userId: $userId");
    }
  }

  Future<void> saveNotes({required bool isSaved}) async {
    if (_isSaving) return;
    _isSaving = true;

    // Get the current user's ID
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      print("Error: User not logged in.");
      return;
    }

    List<Map<String, String>> contentList = [];
    DateTime now = DateTime.now();

    // Collect note content (text and images)
    for (var content in contentWidgets) {
      if (content is TextField) {
        if (content.controller?.text.isNotEmpty ?? false) {
          contentList.add({
            "type": "text",
            "value": content.controller?.text ?? "",
          });
        }
      }
    }

    // Ensure images are always uploaded even if only one remains
    for (var imageUrl in uploadedImageUrls) {
      if (imageUrl.isNotEmpty) {
        contentList.add({
          "type": "image",
          "value": imageUrl,
        });
      }
    }

    try {
      // Save the note to Firestore
      await FirebaseFirestore.instance.collection('notes').add({
        'username': username,
        'userId': userId,
        'title': titleController.text.trim(),
        'note': contentList,
        'color': color,
        'createdAt': now,
        'category': selectedCategory,
        'saved': isSaved,
      });

      // Add data to dailytracker if the category is 'Learning' or 'Add Value'
      if (selectedCategory == "Learning") {
        await _saveDailyActivity(learning: true);
      } else if (selectedCategory == "Add Value") {
        await _saveDailyActivity(addValue: true);
      }

      // Show a confirmation message
      if (_mounted) {
        CustomSnackBar.showCustomSnackBar(
          context,
          isSaved ? "Note saved successfully." : "Note posted successfully.",
          Colors.white,
        );
      }
    } catch (e) {
      print("Error saving note: $e");
    }

    _isSaving = false;
  }

  Future<String> uploadImageToFirebase(File imageFile) async {
    try {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      Reference storageRef =
          FirebaseStorage.instance.ref().child('notes_images/$fileName.jpg');

      UploadTask uploadTask = storageRef.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("Error uploading image: $e");
      return "";
    }
  }

  void pickImage() async {
    final List<XFile>? images = await _picker.pickMultiImage();

    if (images != null && images.isNotEmpty) {
      if (!mounted) return;

      List<String> newUploadedUrls = [];

      for (var image in images) {
        if (!mounted) return;

        setState(() {
          uploadedImageUrls.add("loading"); // Add a temporary loading state
        });

        String imageUrl = await uploadImageToFirebase(File(image.path));

        if (imageUrl.isNotEmpty && mounted) {
          setState(() {
            int loadingIndex = uploadedImageUrls.indexOf("loading");
            if (loadingIndex != -1) {
              uploadedImageUrls[loadingIndex] = imageUrl;
              _validateForm(); // Replace loading with actual URL
            } else {
              uploadedImageUrls.add(imageUrl);
            }
          });
        }
      }
    }
  }

  Future<void> removeImage(int index) async {
    if (!mounted || index < 0 || index >= uploadedImageUrls.length) return;

    String imageUrl = uploadedImageUrls[index];
    setState(() {
      uploadedImageUrls.removeAt(index);
      _validateForm();
    });

    await FirebaseFirestore.instance
        .collection('notes')
        .where('note', arrayContains: {"type": "image", "value": imageUrl})
        .get()
        .then((querySnapshot) {
          for (var doc in querySnapshot.docs) {
            doc.reference.update({
              'note': FieldValue.arrayRemove([
                {"type": "image", "value": imageUrl}
              ])
            });
          }
        });

    await deleteImageFromFirebase(imageUrl);
  }

  Future<void> deleteImageFromFirebase(String imageUrl) async {
    try {
      Reference storageRef = FirebaseStorage.instance.refFromURL(imageUrl);
      await storageRef.delete();
    } catch (e) {
      print("Error deleting image: $e");
    }
  }

  Widget buildImageSlider() {
    return Center(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: uploadedImageUrls.isEmpty
            ? SizedBox()
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                physics: BouncingScrollPhysics(),
                itemCount: uploadedImageUrls.length,
                itemBuilder: (context, index) {
                  double screenWidth = MediaQuery.of(context).size.width;
                  double imageWidth = screenWidth * 0.8;
                  double imageHeight = screenWidth * 1;

                  return Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: screenWidth * 0.02),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: uploadedImageUrls[index] == "loading"
                                ? Container(
                                    width: imageWidth,
                                    height: imageHeight,
                                    color: Colors.grey[300],
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : Image.network(
                                    uploadedImageUrls[index],
                                    width: imageWidth,
                                    height: imageHeight,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          Positioned(
                            top: 5,
                            right: 5,
                            child: GestureDetector(
                              onTap: () => removeImage(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void addText(String text) {
    if (text.isNotEmpty) {
      setState(() {
        contentWidgets.add(
          TextField(
            controller: TextEditingController(text: text),
            maxLines: null,
            decoration: InputDecoration(border: InputBorder.none),
            onSubmitted: (value) {
              addText(value);
            },
          ),
        );
      });
    }
  }
}
