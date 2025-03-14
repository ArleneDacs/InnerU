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
                item["value"]!, // Fetch image from Firebase Storage URL
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
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
    _mounted = false; // Mark the widget as unmounted when disposed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.arrow_back)),
        actions: <Widget>[
          TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Post this note?",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    content: Text(
                        "Are you sure you want to share this note with the community?"),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context); // Close the dialog
                        },
                        child: Text("Cancel"),
                      ),
                      TextButton(
                        onPressed: () {
                          saveNotes(); // Save the note
                          _finishedWriting();
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                        child:
                            Text("Yes", style: TextStyle(color: Colors.green)),
                      ),
                    ],
                  ),
                );
              },
              child: Text(
                "Post",
                style: TextStyle(fontSize: 15),
              ))
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
                },
              ),
            ),
            SizedBox(
              height: 20,
            ),
            TextField(
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              controller: titleController,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Title",
              ),
              onChanged: (value) {
                titleString = value;
              },
            ),
            Expanded(
                child: ListView.builder(
                    itemCount: contentWidgets.length,
                    itemBuilder: (context, index) {
                      return contentWidgets[index];
                    })),
            TextField(
              controller: contentController,
              maxLines: null,
              decoration: InputDecoration(
                border: InputBorder.none,
              ),
              onSubmitted: (value) {
                addText(value);
              },
            ),
            ElevatedButton(
              onPressed: pickImage,
              child: Icon(
                Icons.image_search,
                size: 30,
              ),
            ),
          ],
        ),
      )),
    );
  }

  Future<void> _saveDailyActivity(
      {bool meditation = false,
      bool steps = false,
      bool learning = false,
      bool addValue = false}) async {
    String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    FirebaseFirestore firestore = FirebaseFirestore.instance;

    // Fetch username from Firestore user document
    DocumentSnapshot userDoc =
        await firestore.collection('users').doc(userId).get();
    String? username = userDoc.get('username');

    if (username != null) {
      String formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DocumentReference docRef =
          firestore.collection('dailytracker').doc('$username-$formattedDate');

      // Use Firestore's FieldValue.merge to update without overwriting other fields
      await docRef.set({
        'username': username,
        'date': formattedDate,
        if (meditation) 'meditation': true,
        if (steps) 'steps': true,
        if (learning) 'learning': true,
        if (addValue) 'addValue': true
      }, SetOptions(merge: true));

      print("Successfully updated the daily tracker.");
    } else {
      print("Error: Username not found for userId: $userId");
    }
  }

  void _finishedWriting() async {
    if (selectedCategory == "Learning") {
      await _saveDailyActivity(learning: true);
    } else if (selectedCategory == "Add Value") {
      await _saveDailyActivity(addValue: true);
    }
  }

  Future<void> saveNotes() async {
    if (_isSaving) return;
    _isSaving = true;
    List<Map<String, String>> contentList = [];
    DateTime now = DateTime.now();

    for (var content in contentWidgets) {
      if (content is TextField) {
        if (content.controller?.text.isNotEmpty ?? false) {
          contentList.add({
            "type": "text",
            "value": content.controller?.text ?? "",
          });
        }
      } else if (content is Padding && content.child is Image) {
        Image imageWidget = content.child as Image;

        if (imageWidget.image is NetworkImage) {
          String imageUrl = (imageWidget.image as NetworkImage).url;
          contentList.add({
            "type": "image",
            "value": imageUrl,
          });
        }
      }
    }

    try {
      if (note.id.isEmpty) {
        final querySnapshot = await myNotes
            .where('username', isEqualTo: username)
            .where('title', isEqualTo: titleString)
            .get();

        if (querySnapshot.docs.isEmpty) {
          await myNotes.add({
            'username': username,
            'title': titleString,
            'note': contentList,
            'color': color,
            'createdAt': now,
            'category': selectedCategory
          });

          if (_mounted) {
            CustomSnackBar.showCustomSnackBar(
                context, "Note saved successfully.", Colors.white);
          }
        }
      }
    } catch (e) {
      if (_mounted) {
        CustomSnackBar.showCustomSnackBar(context, e.toString(), Colors.white);
      }
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

      return await snapshot.ref.getDownloadURL(); // Get image URL
    } catch (e) {
      print("Error uploading image: $e");
      return "";
    }
  }

  void pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      File imageFile = File(image.path);

      // Upload image to Firebase Storage
      String imageUrl = await uploadImageToFirebase(imageFile);

      if (imageUrl.isNotEmpty) {
        setState(() {
          contentWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Image.network(
                imageUrl,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          );
        });
      }
    }
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
