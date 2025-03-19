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
              child: ListView(
                children: [
                  ...contentWidgets, // Ensure existing text fields are shown first
                  buildImageSlider(), // Move image previews below text inputs
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
/// Function to save notes (including uploaded images)
Future<void> saveNotes() async {
  if (_isSaving) return;
  _isSaving = true;
  List<Map<String, String>> contentList = [];
  DateTime now = DateTime.now();

  // Add text content
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

  // Add uploaded image URLs
  for (var imageUrl in uploadedImageUrls) {
    contentList.add({
      "type": "image",
      "value": imageUrl,
    });
  }

  try {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('notes')
        .where('username', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .where('title', isEqualTo: "Note Title") // Change as needed
        .get();

    if (querySnapshot.docs.isEmpty) {
      await FirebaseFirestore.instance.collection('notes').add({
        'username': username,
        'title': titleString, // Update this dynamically
        'note': contentList,
        'color':color, // Change based on user selection
        'createdAt': now,
        'category': selectedCategory
      });

      if (_mounted) {
        CustomSnackBar.showCustomSnackBar(
            context, "Note saved successfully.", Colors.white);
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

    return await snapshot.ref.getDownloadURL();
  } catch (e) {
    print("Error uploading image: $e");
    return "";
  }
}
void pickImage() async {
  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

  if (image != null) {
    setState(() {
      _selectedImage = image;
      imagePaths.add(image.path); // Store local path for UI preview
    });

    // Upload image to Firebase and store the URL
  String imageUrl = await uploadImageToFirebase(File(image.path));
if (imageUrl.isNotEmpty && mounted) { // Check if widget is still in the tree
  setState(() {
    uploadedImageUrls.add(imageUrl);
  });
}   
  }
}

Widget buildImageSlider() {
  return Center(
    child: SizedBox(
      height: MediaQuery.of(context).size.height * 0.5, // 40% of screen height
      child: imagePaths.isEmpty
          ? SizedBox() // Show nothing if there are no images
          : ListView.builder(
              scrollDirection: Axis.horizontal, // Make images slide horizontally
              shrinkWrap: true,
              physics: BouncingScrollPhysics(),
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                double screenWidth = MediaQuery.of(context).size.width;
                double imageWidth = screenWidth * 0.8; // 70% of screen width
                double imageHeight = screenWidth * 1; // 80% of screen width

                return Align(
                  alignment: Alignment.center, // Center images
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.02), // Responsive padding
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12), // Rounded corners
                          child: Image.file(
                            File(imagePaths[index]), 
                            width: imageWidth, 
                            height: imageHeight, 
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                imagePaths.removeAt(index); // Remove image on tap
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.8), // Semi-transparent
                                shape: BoxShape.circle,
                              ),
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.close, color: Colors.white, size: 18),
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
