import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/step_submission_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// Lets a mentee log a day's steps that weren't picked up automatically,
/// with a photo as proof, sent to their coach for approval. Nothing is
/// written to the real daily tracker until the coach approves it.
class StepSubmissionScreen extends StatefulWidget {
  const StepSubmissionScreen({super.key});

  @override
  State<StepSubmissionScreen> createState() => _StepSubmissionScreenState();
}

class _StepSubmissionScreenState extends State<StepSubmissionScreen> {
  final TextEditingController _stepsController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  Uint8List? _proofBytes;
  String? _proofFileName;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _stepsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickProofImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _proofBytes = bytes;
      _proofFileName = picked.name;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    final steps = int.tryParse(_stepsController.text.trim());
    if (steps == null || steps <= 0) {
      setState(() => _error = 'Enter a valid step count.');
      return;
    }
    if (_proofBytes == null) {
      setState(() => _error = 'Attach a photo as proof.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final proofUrl = await ImageStorageService.uploadStepProofBytes(
        _proofBytes!,
        fileName: _proofFileName ?? 'step-proof.jpg',
      );
      if (proofUrl == null || proofUrl.trim().isEmpty) {
        throw Exception('Could not upload the proof photo.');
      }

      await StepSubmissionApiService.instance.submit(
        steps: steps,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        proofUrl: proofUrl,
        note: _noteController.text,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to your coach for approval.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not submit. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, theme) {
        return Theme(
          data: AppTheme.company(theme),
          child: Scaffold(
            backgroundColor: theme.backgroundColor,
            appBar: AppBar(
              backgroundColor: theme.surfaceColor,
              foregroundColor: theme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Submit steps for approval',
                style: TextStyle(color: theme.inkColor),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Log a day's steps that weren't tracked automatically. "
                    "Your coach reviews the photo before it's added to your "
                    'records.',
                    style: TextStyle(color: theme.mutedInkColor, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Date',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: theme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat.yMMMd().format(_selectedDate),
                            style: TextStyle(color: theme.inkColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Step count',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _stepsController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: theme.inkColor),
                    decoration: InputDecoration(
                      hintText: 'e.g. 8500',
                      filled: true,
                      fillColor: theme.surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Proof photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickProofImage,
                    child: Container(
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: theme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.24),
                        ),
                      ),
                      child: _proofBytes == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo_outlined,
                                  color: theme.mutedInkColor,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Attach a screenshot of your phone's "
                                  'step count',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: theme.mutedInkColor),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _proofBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 180,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Note (optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    style: TextStyle(color: theme.inkColor),
                    decoration: InputDecoration(
                      hintText: 'Anything your coach should know?',
                      filled: true,
                      fillColor: theme.surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB55D5D)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send to coach'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
