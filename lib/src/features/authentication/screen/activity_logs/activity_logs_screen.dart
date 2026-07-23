import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/activity_logs_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key, this.debugLoader});

  final Future<ActivityLogsSnapshot> Function()? debugLoader;

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen>
    with WidgetsBindingObserver {
  late Future<ActivityLogsSnapshot> _futureSnapshot;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _futureSnapshot = _load();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<ActivityLogsSnapshot> _load() {
    return widget.debugLoader?.call() ?? ActivityLogsService.instance.loadToday();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureSnapshot = _load();
    });
    await _futureSnapshot;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  IconData _iconFor(ActivityLogKind kind) {
    return switch (kind) {
      ActivityLogKind.meditation => Icons.self_improvement_rounded,
      ActivityLogKind.steps => Icons.directions_walk_rounded,
      ActivityLogKind.exercise => Icons.fitness_center_rounded,
      ActivityLogKind.fasting => Icons.local_fire_department_rounded,
      ActivityLogKind.calories => Icons.restaurant_rounded,
      ActivityLogKind.sleep => Icons.bedtime_rounded,
    };
  }

  Color _colorFor(CompanyThemeData theme, ActivityLogKind kind) {
    return switch (kind) {
      ActivityLogKind.meditation => theme.primaryColor,
      ActivityLogKind.steps => theme.iconColor,
      ActivityLogKind.exercise => const Color(0xFFCE8F5A),
      ActivityLogKind.fasting => const Color(0xFFD95555),
      ActivityLogKind.calories => const Color(0xFF7A8E59),
      ActivityLogKind.sleep => const Color(0xFF6D849A),
    };
  }

  String _dayLabel(DateTime value) {
    return DateFormat('EEEE, MMMM d').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              surfaceTintColor: Colors.transparent,
              foregroundColor: companyTheme.inkColor,
              title: const Text('Activity Logs'),
            ),
            body: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<ActivityLogsSnapshot>(
                future: _futureSnapshot,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 180),
                        Center(child: CircularProgressIndicator()),
                      ],
                    );
                  }

                  final data = snapshot.data ??
                      ActivityLogsSnapshot.empty(
                        detail: 'No activity logs available right now.',
                      );

                  if (data.items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SizedBox(height: 28),
                        _buildEmptyState(companyTheme, data),
                      ],
                    );
                  }

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _buildSummaryCard(companyTheme, data),
                      const SizedBox(height: 16),
                      for (final item in data.items) ...[
                        _buildActivityCard(companyTheme, item),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard(
    CompanyThemeData theme,
    ActivityLogsSnapshot snapshot,
  ) {
    final surface = theme.isDark ? theme.surfaceColor : const Color(0xFFF7F1E5);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.isDark
              ? theme.iconColor.withValues(alpha: 0.24)
              : const Color(0xFFE4D8C3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dayLabel(DateTime.now()),
            style: TextStyle(
              color: theme.mutedInkColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${snapshot.totalItems} activity log${snapshot.totalItems == 1 ? '' : 's'} today',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A quick glance at meditation, steps, exercise, fasting, calories, and sleep.',
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
    CompanyThemeData theme,
    ActivityLogItem item,
  ) {
    final accent = _colorFor(theme, item.kind);
    final surface = theme.isDark ? theme.surfaceColor : Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.isDark
              ? theme.iconColor.withValues(alpha: 0.18)
              : const Color(0xFFE8E1D5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: theme.isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_iconFor(item.kind), color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.detail,
                  style: TextStyle(
                    color: theme.mutedInkColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: theme.inkColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    CompanyThemeData theme,
    ActivityLogsSnapshot snapshot,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.surfaceColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.isDark
              ? theme.iconColor.withValues(alpha: 0.2)
              : const Color(0xFFE8E1D5),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 64,
            color: theme.mutedInkColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No activity logs yet',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.items.isEmpty
                ? 'Your meditation, steps, exercise, fasting, calories, and sleep logs will show here.'
                : snapshot.items.first.detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.mutedInkColor, height: 1.4),
          ),
        ],
      ),
    );
  }
}
