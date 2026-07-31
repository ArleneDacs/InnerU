import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/accountability_meeting_api_service.dart';

/// Shows the "schedule an accountability meeting" form for a specific
/// group. Returns true if a meeting was successfully scheduled.
Future<bool?> showScheduleMeetingDialog(
  BuildContext context, {
  required String groupId,
  required String groupName,
  String? meetingId,
  String? initialTitle,
  String? initialZoomLink,
  String? initialNotes,
  DateTime? initialScheduledAt,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ScheduleMeetingDialog(
      groupId: groupId,
      groupName: groupName,
      meetingId: meetingId,
      initialTitle: initialTitle,
      initialZoomLink: initialZoomLink,
      initialNotes: initialNotes,
      initialScheduledAt: initialScheduledAt,
    ),
  );
}

class _ScheduleMeetingDialog extends StatefulWidget {
  const _ScheduleMeetingDialog({
    required this.groupId,
    required this.groupName,
    this.meetingId,
    this.initialTitle,
    this.initialZoomLink,
    this.initialNotes,
    this.initialScheduledAt,
  });

  final String groupId;
  final String groupName;
  final String? meetingId;
  final String? initialTitle;
  final String? initialZoomLink;
  final String? initialNotes;
  final DateTime? initialScheduledAt;

  @override
  State<_ScheduleMeetingDialog> createState() => _ScheduleMeetingDialogState();
}

class _ScheduleMeetingDialogState extends State<_ScheduleMeetingDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _zoomLinkController;
  late final TextEditingController _notesController;
  DateTime? _date;
  TimeOfDay? _time;
  bool _isSubmitting = false;
  String? _error;

  bool get _isEditing => widget.meetingId != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _zoomLinkController =
        TextEditingController(text: widget.initialZoomLink ?? '');
    _notesController = TextEditingController(text: widget.initialNotes ?? '');

    final initialScheduledAt = widget.initialScheduledAt;
    if (initialScheduledAt != null) {
      _date = DateTime(
        initialScheduledAt.year,
        initialScheduledAt.month,
        initialScheduledAt.day,
      );
      _time = TimeOfDay.fromDateTime(initialScheduledAt);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _zoomLinkController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: _isEditing ? DateTime(2000) : now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final zoomLink = _zoomLinkController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Give the meeting a title.');
      return;
    }
    if (zoomLink.isEmpty) {
      setState(() => _error = 'Add the Zoom link.');
      return;
    }
    if (_date == null || _time == null) {
      setState(() => _error = 'Pick a date and time.');
      return;
    }

    final scheduledAt = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    if (!_isEditing && !scheduledAt.isAfter(DateTime.now())) {
      setState(() => _error = 'Pick a time in the future.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      if (_isEditing) {
        await AccountabilityMeetingApiService.instance.update(
          meetingId: widget.meetingId!,
          title: title,
          zoomLink: zoomLink,
          scheduledAt: scheduledAt,
          notes: _notesController.text,
        );
      } else {
        await AccountabilityMeetingApiService.instance.schedule(
          groupId: widget.groupId,
          title: title,
          zoomLink: zoomLink,
          scheduledAt: scheduledAt,
          notes: _notesController.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _isEditing
            ? 'Could not save the changes. Please try again.'
            : 'Could not schedule the meeting. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        _date == null ? 'Pick a date' : DateFormat.yMMMd().format(_date!);
    final timeLabel = _time == null ? 'Pick a time' : _time!.format(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        _isEditing
            ? 'Edit meeting — ${widget.groupName}'
            : 'Schedule meeting — ${widget.groupName}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Weekly accountability check-in',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zoomLinkController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Zoom link',
                hintText: 'https://zoom.us/j/...',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickDate,
                    child: Text(dateLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickTime,
                    child: Text(timeLabel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
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
              : Text(_isEditing ? 'Save changes' : 'Schedule'),
        ),
      ],
    );
  }
}
