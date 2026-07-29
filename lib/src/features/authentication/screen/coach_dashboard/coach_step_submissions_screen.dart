import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/step_submission_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// Coach-facing queue of manual step submissions from mentees, each with a
/// photo as proof. Approving writes the steps into the mentee's real daily
/// tracker; declining requires a reason so the mentee knows why.
class CoachStepSubmissionsScreen extends StatefulWidget {
  const CoachStepSubmissionsScreen({super.key});

  @override
  State<CoachStepSubmissionsScreen> createState() =>
      _CoachStepSubmissionsScreenState();
}

class _CoachStepSubmissionsScreenState
    extends State<CoachStepSubmissionsScreen> {
  final StepSubmissionApiService _api = StepSubmissionApiService.instance;
  final Set<String> _actingOnIds = <String>{};

  Future<void> _approve(String id) async {
    setState(() => _actingOnIds.add(id));
    try {
      await _api.approve(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Approved and added to their tracker.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not approve. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _actingOnIds.remove(id));
      }
    }
  }

  Future<void> _decline(String id) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DeclineReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _actingOnIds.add(id));
    try {
      await _api.decline(id, reason.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Declined.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not decline. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _actingOnIds.remove(id));
      }
    }
  }

  void _viewProof(CompanyThemeData theme, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                ImageStorageService.normalizeMediaUrl(url),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 240,
                  color: theme.surfaceColor,
                  alignment: Alignment.center,
                  child: Text(
                    'Could not load photo.',
                    style: TextStyle(color: theme.mutedInkColor),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        ),
      ),
    );
  }

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
                'Step submissions',
                style: TextStyle(color: theme.inkColor),
              ),
            ),
            body: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _api.watchForCoach(),
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
                      'No step submissions yet.',
                      style: TextStyle(color: theme.mutedInkColor),
                    ),
                  );
                }

                final pending =
                    items.where((s) => s['status'] == 'pending').toList();
                final reviewed =
                    items.where((s) => s['status'] != 'pending').toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (pending.isNotEmpty) ...[
                      Text(
                        'Pending (${pending.length})',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.inkColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...pending.map((s) => _buildCard(theme, s)),
                      const SizedBox(height: 20),
                    ],
                    if (reviewed.isNotEmpty) ...[
                      Text(
                        'Reviewed',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.inkColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...reviewed.map((s) => _buildCard(theme, s)),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(CompanyThemeData theme, Map<String, dynamic> submission) {
    final id = (submission['id'] as String?) ?? '';
    final menteeName =
        (submission['menteeName'] as String?)?.trim().isNotEmpty == true
            ? (submission['menteeName'] as String).trim()
            : 'Mentee';
    final steps = (submission['steps'] as num?)?.toInt() ?? 0;
    final dateRaw = submission['date'] as String?;
    final date = dateRaw != null ? DateTime.tryParse(dateRaw) : null;
    final note = (submission['note'] as String?)?.trim();
    final proofUrl = (submission['proofUrl'] as String?) ?? '';
    final status = (submission['status'] as String?) ?? 'pending';
    final declineReason = (submission['declineReason'] as String?)?.trim();
    final isPending = status == 'pending';
    final isActing = _actingOnIds.contains(id);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      menteeName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.inkColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date != null
                          ? DateFormat.yMMMd().format(date)
                          : 'Unknown date',
                      style: TextStyle(color: theme.mutedInkColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap:
                    proofUrl.isEmpty ? null : () => _viewProof(theme, proofUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: proofUrl.isEmpty
                      ? Container(
                          width: 72,
                          height: 72,
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: theme.mutedInkColor,
                          ),
                        )
                      : Image.network(
                          ImageStorageService.normalizeMediaUrl(proofUrl),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 72,
                            height: 72,
                            color: theme.primaryColor.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: theme.mutedInkColor,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$steps steps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: theme.inkColor,
                      ),
                    ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        style: TextStyle(color: theme.mutedInkColor),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!isPending &&
              status == 'declined' &&
              declineReason != null &&
              declineReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFB55D5D).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Reason: $declineReason',
                style: TextStyle(color: theme.mutedInkColor, fontSize: 13),
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isActing ? null : () => _decline(id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB55D5D),
                      side: BorderSide(
                        color: const Color(0xFFB55D5D).withValues(alpha: 0.32),
                      ),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isActing ? null : () => _approve(id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor:
                          theme.isDark ? theme.backgroundColor : Colors.white,
                    ),
                    child: isActing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Approve'),
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

class _DeclineReasonDialog extends StatefulWidget {
  @override
  State<_DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<_DeclineReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Decline submission'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Let your mentee know why this was declined.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Reason for declining',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB55D5D),
          ),
          onPressed: () {
            final reason = _controller.text.trim();
            if (reason.isEmpty) {
              setState(() => _error = 'A reason is required.');
              return;
            }
            Navigator.pop(context, reason);
          },
          child: const Text('Decline'),
        ),
      ],
    );
  }
}
