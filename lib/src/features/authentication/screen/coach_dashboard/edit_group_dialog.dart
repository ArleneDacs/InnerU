import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

/// Shows the "edit group" form: rename and/or change the group's photo.
/// Returns true if a change was saved.
Future<bool?> showEditGroupDialog(
  BuildContext context, {
  required String groupId,
  required String currentName,
  String? currentPhotoUrl,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _EditGroupDialog(
      groupId: groupId,
      currentName: currentName,
      currentPhotoUrl: currentPhotoUrl,
    ),
  );
}

class _EditGroupDialog extends StatefulWidget {
  const _EditGroupDialog({
    required this.groupId,
    required this.currentName,
    required this.currentPhotoUrl,
  });

  final String groupId;
  final String currentName;
  final String? currentPhotoUrl;

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.currentName);
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _newPhotoBytes;
  String? _newPhotoFileName;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _newPhotoBytes = bytes;
      _newPhotoFileName = picked.name;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      String? photoUrl;
      if (_newPhotoBytes != null) {
        photoUrl = await ImageStorageService.uploadGroupPhotoBytes(
          _newPhotoBytes!,
          fileName: _newPhotoFileName ?? 'group-photo.jpg',
        );
        if (photoUrl == null || photoUrl.trim().isEmpty) {
          throw Exception('Could not upload the photo.');
        }
      }

      await CoachApiService.instance.updateGroup(
        groupId: widget.groupId,
        name: name == widget.currentName ? null : name,
        photoUrl: photoUrl,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save changes. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Edit group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: _newPhotoBytes != null
                          ? MemoryImage(_newPhotoBytes!)
                          : (widget.currentPhotoUrl?.isNotEmpty == true
                              ? NetworkImage(
                                  ImageStorageService.normalizeMediaUrl(
                                    widget.currentPhotoUrl,
                                  ),
                                ) as ImageProvider
                              : null),
                      child: _newPhotoBytes == null &&
                              (widget.currentPhotoUrl?.isEmpty ?? true)
                          ? const Icon(Icons.groups, size: 32)
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB55D5D)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
