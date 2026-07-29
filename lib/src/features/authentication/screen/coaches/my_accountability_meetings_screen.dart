import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/accountability_meeting_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// A mentee's upcoming accountability meetings for the groups they belong
/// to. Joining marks attendance (which checks off today's Call task on the
/// real daily tracker) and opens the Zoom link. Also the one place that
/// schedules the on-device day-before/day-of reminders, since there's no
/// server push in this app to wake the client otherwise.
class MyAccountabilityMeetingsScreen extends StatefulWidget {
  const MyAccountabilityMeetingsScreen({super.key});

  @override
  State<MyAccountabilityMeetingsScreen> createState() =>
      _MyAccountabilityMeetingsScreenState();
}

class _MyAccountabilityMeetingsScreenState
    extends State<MyAccountabilityMeetingsScreen> {
  final Set<String> _remindersScheduledForIds = <String>{};
  final Set<String> _joiningIds = <String>{};

  void _ensureLocalReminders(List<Map<String, dynamic>> meetings) {
    for (final meeting in meetings) {
      final id = (meeting['id'] as String?) ?? '';
      if (id.isEmpty || _remindersScheduledForIds.contains(id)) continue;
      final scheduledAtRaw = meeting['scheduledAt'] as String?;
      final scheduledAt =
          scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw) : null;
      if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now())) {
        continue;
      }
      _remindersScheduledForIds.add(id);
      final title = (meeting['title'] as String?)?.trim().isNotEmpty == true
          ? (meeting['title'] as String).trim()
          : 'Accountability meeting';
      FastingNotificationService.instance.scheduleMeetingReminders(
        meetingId: id,
        title: title,
        scheduledAt: scheduledAt,
      );
    }
  }

  Future<void> _join(Map<String, dynamic> meeting) async {
    final id = (meeting['id'] as String?) ?? '';
    if (id.isEmpty || _joiningIds.contains(id)) return;

    setState(() => _joiningIds.add(id));
    try {
      final response = await AccountabilityMeetingApiService.instance.join(id);
      final zoomLink =
          (response['zoomLink'] as String?)?.trim().isNotEmpty == true
              ? (response['zoomLink'] as String).trim()
              : ((meeting['zoomLink'] as String?)?.trim() ?? '');

      if (zoomLink.isNotEmpty) {
        final uri = Uri.tryParse(zoomLink);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "You're marked as joined — today's Call task is checked off."),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not join. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _joiningIds.remove(id));
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
                'Accountability meetings',
                style: TextStyle(color: theme.inkColor),
              ),
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: AccountabilityMeetingApiService.instance.watchMine(),
              builder: (context, snapshot) {
                final meetings = snapshot.data;
                if (meetings == null &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = meetings ?? const <Map<String, dynamic>>[];
                _ensureLocalReminders(items);

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
    final id = (meeting['id'] as String?) ?? '';
    final title = (meeting['title'] as String?)?.trim().isNotEmpty == true
        ? (meeting['title'] as String).trim()
        : 'Accountability meeting';
    final groupName = (meeting['groupName'] as String?)?.trim();
    final notes = (meeting['notes'] as String?)?.trim();
    final scheduledAtRaw = meeting['scheduledAt'] as String?;
    final scheduledAt =
        scheduledAtRaw != null ? DateTime.tryParse(scheduledAtRaw) : null;
    final hasJoined = meeting['hasJoined'] == true;
    final isJoining = _joiningIds.contains(id);

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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.videocam_outlined, color: theme.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: theme.inkColor,
                      ),
                    ),
                    if (groupName != null && groupName.isNotEmpty)
                      Text(
                        groupName,
                        style: TextStyle(
                          color: theme.mutedInkColor,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (hasJoined)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7E9471).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Joined',
                    style: TextStyle(
                      color: Color(0xFF7E9471),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(notes, style: TextStyle(color: theme.mutedInkColor)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isJoining ? null : () => _join(meeting),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor:
                    theme.isDark ? theme.backgroundColor : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isJoining
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.videocam),
              label: Text(hasJoined ? 'Rejoin meeting' : 'Join meeting'),
            ),
          ),
        ],
      ),
    );
  }
}
