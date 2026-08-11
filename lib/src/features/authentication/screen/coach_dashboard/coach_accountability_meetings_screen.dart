import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/schedule_meeting_dialog.dart';
import 'package:selfcare_projects/src/services/accountability_meeting_api_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// A coach's view across meetings scheduled in any group they manage.
/// Coaches can edit or delete only meetings they personally created;
/// member-created group meetings remain visible here as read-only.
class CoachAccountabilityMeetingsScreen extends StatefulWidget {
  const CoachAccountabilityMeetingsScreen({super.key});

  @override
  State<CoachAccountabilityMeetingsScreen> createState() =>
      _CoachAccountabilityMeetingsScreenState();
}

class _CoachAccountabilityMeetingsScreenState
    extends State<CoachAccountabilityMeetingsScreen> {
  Future<void> _pickGroupAndSchedule(CompanyThemeData theme) async {
    List<Map<String, dynamic>> groups;
    try {
      groups = await CoachApiService.instance.fetchGroups();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load your groups.')),
      );
      return;
    }

    if (groups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a group first.')),
      );
      return;
    }

    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose a group',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              ...groups.map((group) {
                final name =
                    (group['name'] as String?)?.trim().isNotEmpty == true
                        ? (group['name'] as String).trim()
                        : 'Group';
                return ListTile(
                  title: Text(name),
                  onTap: () => Navigator.pop(sheetContext, group),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final groupId = (selected['id'] as String?) ?? '';
    final groupName = (selected['name'] as String?)?.trim().isNotEmpty == true
        ? (selected['name'] as String).trim()
        : 'Group';
    if (groupId.isEmpty) return;

    await showScheduleMeetingDialog(
      context,
      groupId: groupId,
      groupName: groupName,
    );
  }

  Future<void> _editMeeting(Map<String, dynamic> meeting) async {
    final groupId = (meeting['groupId'] as String?)?.trim() ?? '';
    final groupName = (meeting['groupName'] as String?)?.trim() ?? 'Group';
    final meetingId = (meeting['id'] as String?)?.trim() ?? '';
    final title = (meeting['title'] as String?)?.trim() ?? '';
    final zoomLink = (meeting['zoomLink'] as String?)?.trim() ?? '';
    final notes = (meeting['notes'] as String?)?.trim() ?? '';
    final scheduledAtRaw = meeting['scheduledAt'] as String?;
    final scheduledAt =
        scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw) : null;

    if (meetingId.isEmpty || groupId.isEmpty) return;

    final updated = await showScheduleMeetingDialog(
      context,
      groupId: groupId,
      groupName: groupName,
      meetingId: meetingId,
      initialTitle: title,
      initialZoomLink: zoomLink,
      initialNotes: notes,
      initialScheduledAt: scheduledAt,
    );

    if (updated != true || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title updated.')),
    );
  }

  Future<void> _deleteMeeting(Map<String, dynamic> meeting) async {
    final meetingId = (meeting['id'] as String?)?.trim() ?? '';
    final title = (meeting['title'] as String?)?.trim().isNotEmpty == true
        ? (meeting['title'] as String).trim()
        : 'Accountability meeting';
    if (meetingId.isEmpty) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Delete meeting?'),
          content: Text(
            'This will permanently delete "$title".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE56B6F),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await AccountabilityMeetingApiService.instance.delete(meetingId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title deleted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the meeting.')),
      );
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
                'Accountability meetings',
                style: TextStyle(color: theme.inkColor),
              ),
              actions: [
                IconButton(
                  tooltip: 'Schedule meeting',
                  icon: const Icon(Icons.add),
                  onPressed: () => _pickGroupAndSchedule(theme),
                ),
              ],
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: AccountabilityMeetingApiService.instance.watchForCoach(),
              builder: (context, snapshot) {
                final meetings = snapshot.data;
                if (meetings == null &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = meetings ?? const <Map<String, dynamic>>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No accountability meetings scheduled yet.',
                      style: TextStyle(color: theme.mutedInkColor),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _buildCard(theme, items[index]),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(CompanyThemeData theme, Map<String, dynamic> meeting) {
    final title = (meeting['title'] as String?)?.trim().isNotEmpty == true
        ? (meeting['title'] as String).trim()
        : 'Accountability meeting';
    final groupName = (meeting['groupName'] as String?)?.trim();
    final zoomLink = (meeting['zoomLink'] as String?)?.trim() ?? '';
    final menteeCount = (meeting['menteeCount'] as num?)?.toInt();
    final isCreator = meeting['isCreator'] == true;
    final scheduledAtRaw = meeting['scheduledAt'] as String?;
    final scheduledAt =
        scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.inkColor,
                  ),
                ),
              ),
              if (menteeCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$menteeCount mentees',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          if (groupName != null && groupName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(groupName, style: TextStyle(color: theme.mutedInkColor)),
          ],
          const SizedBox(height: 8),
          if (scheduledAt != null)
            Row(
              children: [
                Icon(Icons.event, size: 16, color: theme.mutedInkColor),
                const SizedBox(width: 6),
                Text(
                  DateFormat('EEE, MMM d • h:mm a').format(scheduledAt),
                  style: TextStyle(color: theme.mutedInkColor),
                ),
              ],
            ),
          if (zoomLink.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 16,
                  color: theme.mutedInkColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    zoomLink,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.mutedInkColor),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (isCreator)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _editMeeting(meeting),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.primaryColor,
                      side: BorderSide(
                        color: theme.primaryColor.withValues(alpha: 0.30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text(
                      'Edit',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteMeeting(meeting),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE56B6F),
                      side: BorderSide(
                        color: const Color(0xFFE56B6F).withValues(alpha: 0.30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              'Scheduled by a group member',
              style: TextStyle(
                color: theme.mutedInkColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
