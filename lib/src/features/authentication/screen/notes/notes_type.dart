import 'dart:io';
import 'dart:convert'; // Add this for Base64 encoding

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/UserService.dart';
import 'package:selfcare_projects/src/models/customSnackbar.dart';
import 'package:selfcare_projects/src/models/note_model.dart';

class NotesType extends StatefulWidget {
  final Note note;
  final String? postId; // Nullable para optional
  const NotesType({super.key, required this.note, this.postId});

  @override
  State<NotesType> createState() => _NotesTypeState();
}

class _NotesTypeState extends State<NotesType> {
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

    // Loop through the note content and add widgets
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
      // Your existing loop for note.note contents
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
          // Here we can use Image.network directly for both URLs and Base64
          contentWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Image.network(
                item["value"], // Works with both http URLs and data URLs
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
                          if (widget.postId == 'Learning') {
                            setState(() {
                              todayTasks['Learning'] = true; // Auto-check
                              print('Learning task is now checked ✅');
                            });
                          }
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

  Future<void> saveNotes() async {
    if (_isSaving) return; // Prevent multiple clicks
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
      } else if (content is Padding) {
        // For image widgets
        if (content.child is Stack) {
          final stackWidget = content.child as Stack;
          if (stackWidget.children.isNotEmpty &&
              stackWidget.children[0] is Image) {
            final imageWidget = stackWidget.children[0] as Image;

            if (imageWidget.image is FileImage) {
              // This is a local file image that needs to be converted to Base64
              final fileImage = imageWidget.image as FileImage;
              final File imageFile = fileImage.file;
              final bytes = await imageFile.readAsBytes();
              final base64Image =
                  'data:image/jpeg;base64,${base64Encode(bytes)}';

              contentList.add({
                "type": "image",
                "value": base64Image,
              });
            } else {
              // Handle other image types (should not happen in this flow)
              contentList.add({
                "type": "image",
                "value": imageWidget.image.toString(),
              });
            }
          }
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

    _isSaving = false; // Reset flag after saving
  }

  void pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        contentWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Stack(
              children: [
                Image.file(
                  File(image.path),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: Icon(Icons.cancel, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        contentWidgets.removeLast(); // Remove Image
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );

        // Automatically Add TextField Under Image
        contentWidgets.add(
          TextField(
            controller: TextEditingController(),
            maxLines: null,
            decoration: InputDecoration(border: InputBorder.none),
            onSubmitted: (value) {
              addText(value);
            },
            onChanged: (value) {
              if (value.isEmpty) {
                // If user deletes text, remove image above
                int index = contentWidgets.indexOf(contentWidgets.last);
                if (index > 0 && contentWidgets[index - 1] is Padding) {
                  setState(() {
                    contentWidgets.removeAt(index - 1); // Delete Image
                    contentWidgets.removeAt(index - 1); // Delete TextField
                  });
                }
              }
            },
          ),
        );
      });
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
