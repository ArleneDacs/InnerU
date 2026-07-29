import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/schedule_meeting_dialog.dart';
import 'package:selfcare_projects/src/services/accountability_meeting_api_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// A coach's view across every accountability meeting they've scheduled,
/// for any of their groups. Scheduling a new one from here starts with a
/// group picker since (unlike scheduling from a specific group's card)
/// this screen isn't already scoped to one group.
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
        ],
      ),
    );
  }
}
