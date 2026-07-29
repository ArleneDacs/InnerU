import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notification_api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.userId,
    this.onNotificationTap,
  });

  final String userId;

  // Lets each dashboard own its own screen-specific navigation (e.g. a
  // coach's "mentee applied" notification opens Manage Mentees; a mentee's
  // "coach accepted you" notification opens their coaches list) without
  // this generic screen needing to import every possible destination.
  final void Function(BuildContext context, Map<String, dynamic> notification)?
      onNotificationTap;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationApiService _api = NotificationApiService.instance;
  final Set<String> _locallyReadIds = <String>{};
  CompanyThemeData _theme = CompanyThemeData.standard;

  @override
  void initState() {
    super.initState();
    final cached = CompanyThemeService.cachedThemeForUser(widget.userId);
    if (cached != null) _theme = cached;
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final theme = await CompanyThemeService.resolveForUser(widget.userId);
    if (!mounted) return;
    setState(() => _theme = theme);
  }

  Future<void> _markRead(String notificationId) async {
    setState(() => _locallyReadIds.add(notificationId));
    try {
      await _api.markRead(notificationId);
    } catch (_) {
      // Next poll tick will reconcile if this failed silently.
    }
  }

  Future<void> _markAllRead(List<Map<String, dynamic>> notifications) async {
    setState(() {
      for (final n in notifications) {
        final id = (n['id'] as String?) ?? '';
        if (id.isNotEmpty) _locallyReadIds.add(id);
      }
    });
    try {
      await _api.markAllRead();
    } catch (_) {
      // Next poll tick will reconcile if this failed silently.
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'mentee_request_accepted':
        return CupertinoIcons.checkmark_seal_fill;
      case 'added_to_group':
        return CupertinoIcons.person_3_fill;
      case 'streak_milestone':
        return CupertinoIcons.flame_fill;
      case 'community_comment':
        return CupertinoIcons.chat_bubble_text_fill;
      case 'mentee_request_received':
        return CupertinoIcons.person_add_solid;
      case 'mentee_progress_logged':
        return CupertinoIcons.chart_bar_alt_fill;
      case 'step_submission_received':
        return CupertinoIcons.photo_on_rectangle;
      case 'step_submission_approved':
        return CupertinoIcons.checkmark_circle_fill;
      case 'step_submission_declined':
        return CupertinoIcons.xmark_circle_fill;
      default:
        return CupertinoIcons.bell_fill;
    }
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: theme.iconColor,
        elevation: 0,
        title: Text(
          'Notifications',
          style: TextStyle(color: theme.inkColor, fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _api.watchNotifications(),
        builder: (context, snapshot) {
          final payload = snapshot.data;
          final notifications =
              (payload?['notifications'] as List<Map<String, dynamic>>?) ??
                  const <Map<String, dynamic>>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              notifications.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notifications.isEmpty) {
            return Center(
              child: Text(
                "You're all caught up.",
                style: TextStyle(color: theme.mutedInkColor),
              ),
            );
          }

          final hasUnread = notifications.any((n) {
            final id = (n['id'] as String?) ?? '';
            return n['readAt'] == null && !_locallyReadIds.contains(id);
          });

          return Column(
            children: [
              if (hasUnread)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _markAllRead(notifications),
                    child: const Text('Mark all as read'),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    final id = (notification['id'] as String?) ?? '';
                    final isRead = notification['readAt'] != null ||
                        _locallyReadIds.contains(id);
                    final title = (notification['title'] as String?) ?? '';
                    final body = (notification['body'] as String?)?.trim();
                    final type = (notification['type'] as String?) ?? '';
                    final createdAtRaw = notification['createdAt'];
                    final createdAt = createdAtRaw is String
                        ? DateTime.tryParse(createdAtRaw)
                        : null;

                    return Material(
                      color: isRead
                          ? theme.surfaceColor.withValues(alpha: 0.55)
                          : theme.surfaceColor,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          if (!isRead && id.isNotEmpty) {
                            _markRead(id);
                          }
                          widget.onNotificationTap?.call(context, notification);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor
                                      .withValues(alpha: isRead ? 0.10 : 0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _iconForType(type),
                                  color: theme.primaryColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        color: theme.inkColor,
                                        fontWeight: isRead
                                            ? FontWeight.w600
                                            : FontWeight.w800,
                                      ),
                                    ),
                                    if (body != null && body.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        body,
                                        style: TextStyle(
                                          color: theme.mutedInkColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    if (createdAt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        _relativeTime(createdAt),
                                        style: TextStyle(
                                          color: theme.mutedInkColor
                                              .withValues(alpha: 0.7),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE56B6F),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
