import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/models/customSnackbar.dart';
import 'package:selfcare_projects/src/models/note_model.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/community_api_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class NotesType extends StatefulWidget {
  final Note note;
  final String? postId; // Nullable
  final XFile? initialImage;
  final String? initialCategory;
  final bool openCommunityAfterPost;

  const NotesType({
    super.key,
    required this.note,
    this.postId,
    this.initialImage,
    this.initialCategory,
    this.openCommunityAfterPost = false,
  });

  @override
  State<NotesType> createState() => _NotesTypeState();
}

class _NotesTypeState extends State<NotesType> {
  String? selectedCategory;
  List<Widget> contentWidgets = []; // This will store text and image widgets
  final ImagePicker _picker = ImagePicker();
  List<String> uploadedImageUrls = [];
  List<String> imagePaths = [];

  String username = "Loading...";
  late Note note;
  String titleString = '';
  late List<dynamic> noteString;
  late int color;
  bool _isSaving = false;
  late SnackBar alertContent;

  late TextEditingController titleController;
  late TextEditingController contentController = TextEditingController();

  get todayTasks => null;

  String? _validCategory(String? value) {
    final trimmed = value?.trim();
    if (trimmed == "Add Value" || trimmed == "Learning") {
      return trimmed;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    note = widget.note;
    selectedCategory =
        _validCategory(widget.initialCategory) ?? _validCategory(note.category);
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _validateForm();
      final initialImage = widget.initialImage;
      if (initialImage != null) {
        _addPickedImage(initialImage);
      }
    });
  }

  @override
  void dispose() {
    _isSaving = false; // Mark the widget as unmounted when disposed
    super.dispose();
  }

  bool _isFormValid = false;
  bool _isValidImageUrl(String value) {
    final url = value.trim();
    return url.isNotEmpty &&
        url != "loading" &&
        (url.startsWith("http://") || url.startsWith("https://"));
  }

  void _validateForm() {
    bool hasTitle = titleController.text.trim().isNotEmpty;
    bool hasText = contentWidgets.any((widget) =>
        widget is TextField &&
        (widget.controller?.text.trim().isNotEmpty ?? false));
    bool hasImage = uploadedImageUrls.any(_isValidImageUrl);
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

  Future<void> updateUsernameInComments(
      String userId, String newUsername) async {
    debugPrint(
      'Username backfill is managed server-side for PostgreSQL comments.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        final fieldFillColor =
            companyTheme.isDark ? companyTheme.surfaceColor : Colors.white;
        final panelColor = companyTheme.isDark
            ? companyTheme.surfaceColor
            : Colors.grey.shade100;
        final borderColor = companyTheme.isDark
            ? companyTheme.iconColor.withValues(alpha: 0.42)
            : Colors.teal;

        InputDecoration multilineDecoration(InputDecoration? decoration) {
          return (decoration ?? const InputDecoration()).copyWith(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            fillColor: Colors.transparent,
            hintStyle: TextStyle(color: companyTheme.mutedInkColor),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          );
        }

        return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;

              final shouldLeave = await _showExitConfirmationDialog();
              if (!mounted || !context.mounted) return;
              if (shouldLeave) {
                Navigator.pop(context);
              }
            },
            child: Scaffold(
              backgroundColor: companyTheme.backgroundColor,
              appBar: AppBar(
                backgroundColor: companyTheme.surfaceColor,
                foregroundColor: companyTheme.inkColor,
                iconTheme: IconThemeData(color: companyTheme.inkColor),
                leading: IconButton(
                  onPressed: () async {
                    bool shouldLeave = await _showExitConfirmationDialog();
                    if (!mounted || !context.mounted) return;
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
                              builder: (dialogContext) => AlertDialog(
                                title: Text("Save this note?"),
                                content: Text(
                                    "Do you want to save this note for later?"),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final success =
                                          await saveNotes(isSaved: true);
                                      if (!mounted || !dialogContext.mounted) {
                                        return;
                                      }
                                      Navigator.pop(dialogContext);
                                      if (success) {
                                        Navigator.pop(context);
                                      }
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
                            color: _isFormValid
                                ? companyTheme.inkColor
                                : companyTheme.mutedInkColor)),
                  ),
                  TextButton(
                    onPressed: _isFormValid
                        ? () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text("Post this note?"),
                                content: Text(
                                    "Are you sure you want to share this note?"),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final success =
                                          await saveNotes(isSaved: false);
                                      if (!mounted || !dialogContext.mounted) {
                                        return;
                                      }
                                      Navigator.pop(dialogContext);
                                      if (!success) return;

                                      if (widget.openCommunityAfterPost) {
                                        Navigator.pushReplacementNamed(
                                          context,
                                          '/communityScreen',
                                        );
                                      } else {
                                        Navigator.pop(context);
                                      }
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
                            color: _isFormValid
                                ? companyTheme.inkColor
                                : companyTheme.mutedInkColor)),
                  ),
                ],
              ),
              body: SafeArea(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: panelColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: companyTheme.isDark
                              ? companyTheme.iconColor.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        hint: Text(
                          "Select Category",
                          style: TextStyle(color: companyTheme.mutedInkColor),
                        ),
                        isExpanded: true, // Makes it full-width
                        dropdownColor: fieldFillColor,
                        iconEnabledColor: companyTheme.iconColor,
                        style: TextStyle(color: companyTheme.inkColor),
                        underline: SizedBox.shrink(),
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
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: companyTheme.inkColor,
                        height: 1.25,
                      ),
                      controller: titleController,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 40,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      cursorColor: companyTheme.iconColor,
                      onChanged: (value) => _validateForm(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldFillColor,
                        hintText: "Title",
                        hintStyle: TextStyle(color: companyTheme.mutedInkColor),
                        counterStyle:
                            TextStyle(color: companyTheme.mutedInkColor),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: companyTheme.iconColor,
                            width: 1.5,
                          ),
                        ),
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
                                minLines: 6,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: TextStyle(
                                  color: companyTheme.inkColor,
                                  fontSize: 16,
                                  height: 1.35,
                                ),
                                cursorColor: companyTheme.iconColor,
                                decoration:
                                    multilineDecoration(widget.decoration),
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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: companyTheme.iconColor,
                        foregroundColor:
                            companyTheme.isDark ? Colors.black : Colors.white,
                      ),
                      child: Icon(Icons.image_search, size: 30),
                    ),
                  ],
                ),
              )),
            ));
      },
    );
  }

  Future<void> _saveDailyActivity({
    bool meditation = false,
    bool steps = false,
    bool learning = false,
    bool addValue = false,
  }) async {
    final userId = AuthService.instance.currentSession?.id.toString();
    if (userId == null) return;
    final sessionUser = AuthService.instance.currentSession;
    final displayName = (await UserService.getUserData())['username']?.toString() ??
        sessionUser?.name ??
        'Unknown';
    final membershipData = await CompanyMembershipService.loadForUser(userId);
    await DailyTrackerApiService.instance.upsert(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      meditation: meditation,
      steps: steps,
      learning: learning,
      addValue: addValue,
      username: displayName,
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
    );
  }

  Future<bool> saveNotes({required bool isSaved}) async {
    if (_isSaving) return false;
    _isSaving = true;

    // Get the current user's ID
    final session = AuthService.instance.currentSession;
    final userId = session?.id.toString();
    if (userId == null || session == null) {
      print("Error: User not logged in.");
      _isSaving = false;
      return false;
    }
    final category = selectedCategory?.trim();
    if (category == null || category.isEmpty) {
      _isSaving = false;
      return false;
    }

    List<Map<String, String>> contentList = [];

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
      if (_isValidImageUrl(imageUrl)) {
        contentList.add({
          "type": "image",
          "value": imageUrl,
        });
      }
    }

    try {
      await CommunityApiService.instance.createPost(
        title: titleController.text.trim(),
        category: category,
        note: contentList,
        color: color,
        saved: isSaved,
      );

      // Add data to dailytracker if the category is 'Learning' or 'Add Value'
      if (category == "Learning") {
        await _saveDailyActivity(learning: true);
      } else if (category == "Add Value") {
        await _saveDailyActivity(addValue: true);
      }

      // Show a confirmation message
      if (mounted) {
        CustomSnackBar.showCustomSnackBar(
          context,
          isSaved ? "Note saved successfully." : "Note posted successfully.",
          Colors.white,
        );
      }
      _isSaving = false;
      return true;
    } catch (e) {
      print("Error saving note: $e");
    }

    _isSaving = false;
    return false;
  }

  Future<void> _addPickedImage(XFile image) async {
    if (!ImageStorageService.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Image upload is not configured. Set cloudName/uploadPreset in lib/src/config/cloudinary_config.dart."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      uploadedImageUrls.add("loading");
    });
    _validateForm();

    String imageUrl = await uploadImage(File(image.path));

    if (imageUrl.isNotEmpty && mounted) {
      setState(() {
        // Find the "loading" state and replace it with the actual URL
        int loadingIndex = uploadedImageUrls.indexOf("loading");
        if (loadingIndex != -1) {
          uploadedImageUrls[loadingIndex] = imageUrl;
        } else {
          uploadedImageUrls.add(imageUrl); // Add new image URL
        }
      });
      _validateForm();
    } else if (mounted) {
      final reason = ImageStorageService.lastError;
      setState(() {
        uploadedImageUrls.remove("loading");
      });
      _validateForm();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason == null || reason.isEmpty
              ? "Failed to upload image. Please try again."
              : "Failed to upload image: $reason"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> pickImage() async {
    final List<XFile> images = await _picker.pickMultiImage();

    if (images.isNotEmpty) {
      for (var image in images) {
        await _addPickedImage(image);
      }
    }
  }

  Future<String> uploadImage(File imageFile) async {
    try {
      final imageUrl = await ImageStorageService.uploadImageFile(imageFile);
      return imageUrl ?? "";
    } catch (e) {
      print("Error uploading image: $e");
      return "";
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
                                  color: Colors.grey.withValues(alpha: 0.8),
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

  Future<void> removeImage(int index) async {
    if (!mounted || index < 0 || index >= uploadedImageUrls.length) return;

    String imageUrl = uploadedImageUrls[index];
    setState(() {
      uploadedImageUrls.removeAt(index);
    });

    await deleteImageFromStorage(imageUrl);
  }

  Future<void> deleteImageFromStorage(String imageUrl) async {
    // External unsigned-hosted images are not deleted from the client for safety.
    // We only remove the URL references from Firestore.
    return;
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
