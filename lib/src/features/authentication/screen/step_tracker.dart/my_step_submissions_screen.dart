import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/step_submission_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// A mentee's own step-submission history, so they can see whether a
/// manual entry is still pending, was approved, or was declined (with the
/// coach's reason).
class MyStepSubmissionsScreen extends StatelessWidget {
  const MyStepSubmissionsScreen({super.key});

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF7E9471);
      case 'declined':
        return const Color(0xFFB55D5D);
      default:
        return const Color(0xFFCE8F5A);
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
                'My step submissions',
                style: TextStyle(color: theme.inkColor),
              ),
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: StepSubmissionApiService.instance.watchMine(),
              builder: (context, snapshot) {
                final submissions = snapshot.data;
                if (submissions == null &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = submissions ?? const <Map<String, dynamic>>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      "You haven't submitted any steps yet.",
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

  Widget _buildCard(CompanyThemeData theme, Map<String, dynamic> submission) {
    final steps = (submission['steps'] as num?)?.toInt() ?? 0;
    final dateRaw = submission['date'] as String?;
    final date = dateRaw != null ? DateTime.tryParse(dateRaw) : null;
    final proofUrl = (submission['proofUrl'] as String?) ?? '';
    final status = (submission['status'] as String?) ?? 'pending';
    final declineReason = (submission['declineReason'] as String?)?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: proofUrl.isEmpty
                ? Container(
                    width: 60,
                    height: 60,
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: theme.mutedInkColor,
                    ),
                  )
                : Image.network(
                    ImageStorageService.normalizeMediaUrl(proofUrl),
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 60,
                      height: 60,
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.mutedInkColor,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$steps steps',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.inkColor,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  date != null
                      ? DateFormat.yMMMd().format(date)
                      : 'Unknown date',
                  style: TextStyle(color: theme.mutedInkColor),
                ),
                if (status == 'declined' &&
                    declineReason != null &&
                    declineReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: $declineReason',
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
