import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/fasting_api_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/watch_sync_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class FastingTimerScreen extends StatefulWidget {
  const FastingTimerScreen({super.key});

  @override
  State<FastingTimerScreen> createState() => _FastingTimerScreenState();
}

class _FastingTimerScreenState extends State<FastingTimerScreen> {
  final ActivityStreakService _activityStreakService = ActivityStreakService();
  final FastingApiService _fastingApi = FastingApiService.instance;
  final List<int> _fastingPlans = const [12, 14, 16, 18, 20, 24];

  Timer? _timer;
  int _selectedHours = 16;
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isLoading = true;
  int _lastOngoingNotificationMinute = -1;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadFastingState();
  }

  String get _userId => AuthService.instance.currentSession?.id.toString() ?? '';

  Future<void> _loadFastingState() async {
    try {
      final response = await _fastingApi.fetchSession();
      final session = response['session'];
      final history = response['history'];

      if (!mounted) return;
      setState(() {
        _selectedHours = _readInt(
              session is Map<String, dynamic> ? session['targetHours'] : null,
            ) ??
            16;
        _startTime = _parseDateTime(
          session is Map<String, dynamic> ? session['startTime'] : null,
        );
        _endTime = _parseDateTime(
          session is Map<String, dynamic> ? session['endTime'] : null,
        );
        _history = history is List
            ? history
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList()
            : <Map<String, dynamic>>[];
      });

      if (_startTime != null && _endTime != null) {
        await _syncFastingNotifications();
        _startTicker();
        WatchSyncService.instance.syncFasting(
          active: true,
          start: _startTime,
          goalHours: _selectedHours,
        );
      } else {
        await _clearFastingNotifications();
        WatchSyncService.instance.syncFasting(active: false);
      }
    } catch (error) {
      debugPrint('Failed to load fasting state: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startFast() async {
    final now = DateTime.now();
    final end = now.add(Duration(hours: _selectedHours));

    try {
      await _fastingApi.start(targetHours: _selectedHours);

      setState(() {
        _startTime = now;
        _endTime = end;
      });
      _startTicker();
      WatchSyncService.instance
          .syncFasting(active: true, start: now, goalHours: _selectedHours);
      final notificationsReady = await _syncFastingNotifications();
      _showSnackBar(
        notificationsReady
            ? 'Fasting started. You will get a device notification when it ends.'
            : 'Fasting started, but notifications are unavailable right now.',
      );
    } catch (error) {
      debugPrint('Failed to start fasting timer: $error');
      _showSnackBar('Failed to start fasting timer.');
    }
  }

  Future<void> _endFast() async {
    final startedAt = _startTime;
    final plannedEnd = _endTime;
    final finishedAt = DateTime.now();

    try {
      var completedTarget = false;
      if (startedAt != null) {
        completedTarget =
            plannedEnd != null && !finishedAt.isBefore(plannedEnd);
        await _fastingApi.end();
      }

      if (completedTarget) {
        final unlockedRewards = await _recordFastingStreak();
        if (unlockedRewards.isNotEmpty) {
          _showSnackBar(
              'Fasting medal unlocked: ${unlockedRewards.last.title}');
        }
      }

      _timer?.cancel();
      await _clearFastingNotifications();
      _lastOngoingNotificationMinute = -1;
      setState(() {
        _startTime = null;
        _endTime = null;
      });
      WatchSyncService.instance.syncFasting(active: false);
    } catch (error) {
      debugPrint('Failed to end fasting timer: $error');
      _showSnackBar('Failed to end fasting timer.');
    }
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_endTime != null && DateTime.now().isAfter(_endTime!)) {
        _timer?.cancel();
        _clearFastingNotifications();
        _lastOngoingNotificationMinute = -1;
      }

      setState(() {});
      _updateFastingOngoingNotification();
    });
  }

  Duration _remainingTime() {
    if (_endTime == null) return Duration.zero;
    final remaining = _endTime!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _elapsedTime() {
    if (_startTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_startTime!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double _progress() {
    if (_startTime == null || _endTime == null) return 0;
    final total = _endTime!.difference(_startTime!).inSeconds;
    if (total <= 0) return 0;
    final elapsed =
        DateTime.now().difference(_startTime!).inSeconds.clamp(0, total);
    return elapsed / total;
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _formatClock(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatHours(num value) {
    final formatted = value.toStringAsFixed(1);
    return formatted.endsWith('.0') ? '${value.toInt()}h' : '${formatted}h';
  }

  String _formatShortDateTime(DateTime? value) {
    if (value == null) return '--';
    return DateFormat('MMM d, hh:mm a').format(value);
  }

  String _formatDayTime(DateTime? value) {
    if (value == null) return '--';
    return DateFormat('EEE, HH:mm').format(value);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _updateFastingOngoingNotification({bool force = false}) async {
    if (_startTime == null || _endTime == null) return;

    final remaining = _remainingTime();
    final elapsed = _elapsedTime();
    final elapsedMinute = elapsed.inMinutes;
    if (!force && elapsedMinute == _lastOngoingNotificationMinute) {
      return;
    }

    _lastOngoingNotificationMinute = elapsedMinute;
    try {
      await FastingNotificationService.instance.showFastingOngoingNotification(
        targetHours: _selectedHours,
        elapsed: elapsed,
        remaining: remaining,
      );
    } catch (error) {
      debugPrint('Failed to update fasting ongoing notification: $error');
    }
  }

  Future<bool> _syncFastingNotifications() async {
    if (_endTime == null) return false;

    try {
      await FastingNotificationService.instance.ensurePermissions();
      await FastingNotificationService.instance
          .scheduleFastingCompleteNotification(
        endsAt: _endTime!,
        targetHours: _selectedHours,
      );
      await _updateFastingOngoingNotification(force: true);
      return true;
    } catch (error) {
      debugPrint('Failed to sync fasting notifications: $error');
      return false;
    }
  }

  Future<void> _clearFastingNotifications() async {
    try {
      await FastingNotificationService.instance
          .cancelFastingCompleteNotification();
      await FastingNotificationService.instance
          .cancelFastingOngoingNotification();
    } catch (error) {
      debugPrint('Failed to clear fasting notifications: $error');
    }
  }

  Future<List<ActivityStreakMilestone>> _recordFastingStreak() async {
    try {
      if (_userId.isEmpty) {
        return <ActivityStreakMilestone>[];
      }
      return await _activityStreakService.recordCompletedSession(
        userId: _userId,
        type: ActivityStreakType.fasting,
      );
    } catch (error) {
      debugPrint('Fasting streak update failed: $error');
      return <ActivityStreakMilestone>[];
    }
  }

  void _openFastingRewards() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MeditationStreakRewardsScreen(
          activityType: ActivityStreakType.fasting,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _startTime != null && _endTime != null;
    final progress = _progress();
    final remaining = _remainingTime();
    final elapsed = _elapsedTime();
    final int percent = (progress * 100).round().clamp(0, 100);
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);

              return Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                appBar: AppBar(
                  backgroundColor: companyTheme.surfaceColor,
                  foregroundColor: companyTheme.inkColor,
                  iconTheme: IconThemeData(color: companyTheme.inkColor),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  title: Text(
                    'Fasting',
                    style: TextStyle(
                      color: companyTheme.inkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  actions: [
                    IconButton(
                      onPressed: _openFastingRewards,
                      icon: const Icon(Icons.workspace_premium_rounded),
                      tooltip: 'Rewards',
                    ),
                    IconButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/fastingReports'),
                      icon: const Icon(Icons.insights_outlined),
                      tooltip: 'Reports',
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
                body: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroTimerCard(
                              isActive: isActive,
                              progress: progress,
                              percent: percent,
                              elapsed: elapsed,
                              remaining: remaining,
                            ),
                            const SizedBox(height: 18),
                            _buildQuickActions(isActive),
                            const SizedBox(height: 18),
                            _buildPlanSection(isActive),
                            const SizedBox(height: 18),
                            _buildTimelineSection(isActive),
                            const SizedBox(height: 18),
                            _buildAchievementSection(),
                            const SizedBox(height: 18),
                            _buildHistoryPreview(),
                          ],
                        ),
                      ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeroTimerCard({
    required bool isActive,
    required double progress,
    required int percent,
    required Duration elapsed,
    required Duration remaining,
  }) {
    final theme = Theme.of(context);
    final titleColor = theme.colorScheme.onSurface;
    final accentColor = theme.iconTheme.color ?? theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Fast in progress' : 'Ready to fast',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/fastingReports'),
                icon: const Icon(Icons.auto_graph_rounded, size: 18),
                label: const Text('Reports'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor.withValues(alpha: 0.12),
                  foregroundColor: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 290,
            height: 290,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FastingRingPainter(progress: progress),
                  ),
                ),
                Positioned(
                  top: 28,
                  right: 42,
                  child: _buildFloatingBadge(
                    icon: Icons.local_fire_department_rounded,
                    color: const Color(0xFFFF9A31),
                  ),
                ),
                Positioned(
                  right: 8,
                  child: _buildFloatingBadge(
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFFFFC23A),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 96,
                  child: _buildFloatingBadge(
                    icon: Icons.restaurant_rounded,
                    color: const Color(0xFFFF7A5E),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  child: _buildFloatingBadge(
                    icon: Icons.spa_rounded,
                    color: const Color(0xFF68A5FF),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 94,
                  child: _buildFloatingBadge(
                    icon: Icons.water_drop_rounded,
                    color: const Color(0xFFFF7A5E),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isActive ? 'Elapsed time ($percent%)' : 'Selected fast',
                      style: TextStyle(
                        fontSize: 13,
                        color: titleColor.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isActive
                          ? _formatClock(elapsed)
                          : '$_selectedHours:00:00',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isActive
                          ? 'Your fast ends on'
                          : 'Your plan is ready to start',
                      style: TextStyle(
                        fontSize: 13,
                        color: titleColor.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isActive
                          ? DateFormat('MMM d, hh:mm a').format(_endTime!)
                          : '$_selectedHours hour fasting window',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5F0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Remaining ${_formatClock(remaining)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A4340),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 220,
            child: OutlinedButton(
              onPressed: isActive ? _endFast : _startFast,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: isActive
                      ? const Color(0xFFFF4663)
                      : titleColor.withValues(alpha: 0.24),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                isActive ? 'End Fasting' : 'Start Fasting',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isActive ? const Color(0xFFFF4663) : titleColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingBadge({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildQuickActions(bool isActive) {
    return Row(
      children: [
        Expanded(
          child: _roundedIconAction(
            icon: Icons.timelapse_rounded,
            title: 'Timer',
            subtitle: '${_selectedHours}h goal',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _roundedIconAction(
            icon: Icons.insights_rounded,
            title: 'Reports',
            subtitle: 'Week to year',
            onTap: () => Navigator.pushNamed(context, '/fastingReports'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _roundedIconAction(
            icon: isActive
                ? Icons.pause_circle_outline_rounded
                : Icons.play_circle_fill_rounded,
            title: isActive ? 'Active' : 'Ready',
            subtitle: isActive ? 'Fast running' : 'Start anytime',
          ),
        ),
      ],
    );
  }

  Widget _roundedIconAction({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final accentColor = theme.iconTheme.color ?? theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanSection(bool isActive) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fasting Plans',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isActive
                ? 'Plan stays locked while your current fast is running.'
                : 'Pick the fasting window that fits your day.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _fastingPlans.map((hours) {
              final isSelected = _selectedHours == hours;
              return ChoiceChip(
                label: Text('$hours h'),
                selected: isSelected,
                showCheckmark: false,
                selectedColor: const Color(0xFFFF4663),
                backgroundColor: const Color(0xFFF8F5F0),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF2D2A28),
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide.none,
                onSelected: isActive
                    ? null
                    : (_) {
                        setState(() {
                          _selectedHours = hours;
                        });
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(bool isActive) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _timelineTile(
                  label: 'Start fast',
                  value: isActive ? _formatDayTime(_startTime) : '--',
                  icon: Icons.play_arrow_rounded,
                  color: const Color(0xFFFFD7DF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timelineTile(
                  label: 'End fast',
                  value: isActive ? _formatDayTime(_endTime) : '--',
                  icon: Icons.flag_rounded,
                  color: const Color(0xFFFFEEE3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementSection() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Achievement Medals',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Unlock medals as you complete more fasting goals.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _achievementMedal(
                  title: 'Bronze',
                  subtitle: '3 goal hits',
                  icon: Icons.workspace_premium_rounded,
                  color: const Color(0xFFC78A55),
                  unlocked: _goalHits >= 3,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _achievementMedal(
                  title: 'Silver',
                  subtitle: '7 goal hits',
                  icon: Icons.military_tech_rounded,
                  color: const Color(0xFF98A3B4),
                  unlocked: _goalHits >= 7,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _achievementMedal(
                  title: 'Gold',
                  subtitle: '15 goal hits',
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFFFB52E),
                  unlocked: _goalHits >= 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _achievementMedal({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool unlocked,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: unlocked ? const Color(0xFFFFF8F2) : const Color(0xFFF7F5F3),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: unlocked ? color.withValues(alpha: 0.22) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: unlocked ? color.withValues(alpha: 0.16) : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: unlocked ? color : Colors.black26,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: unlocked ? const Color(0xFF2E2A28) : Colors.black45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            unlocked ? 'Unlocked' : 'Locked',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: unlocked ? color : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F8F6),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF514944)),
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E2A28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPreview() {
    final history = _history.take(6).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Recent Fasts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2E2A28),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/fastingReports'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1F6E66),
                ),
                child: const Text(
                  'View reports',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'No fasting history yet. Your completed fasts will show here.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            Column(
              children: history.map((entry) {
                final targetHours = _readInt(entry['targetHours']) ?? 0;
                final completedHours =
                    (entry['completedHours'] as num?)?.toDouble() ?? 0;
                final completedTarget = entry['completedTarget'] == true;
                final finishedAt = _parseDateTime(entry['finishedAt']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F8F6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: completedTarget
                              ? const Color(0xFFFFEEF2)
                              : const Color(0xFFFFF3E7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          completedTarget
                              ? Icons.check_rounded
                              : Icons.schedule_rounded,
                          color: completedTarget
                              ? const Color(0xFFFF4663)
                              : const Color(0xFFFF9A31),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatHours(completedHours)} completed',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2E2A28),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_formatShortDateTime(finishedAt)} • Goal ${targetHours}h',
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: completedTarget
                              ? const Color(0xFFFFEEF2)
                              : const Color(0xFFFFF3E7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          completedTarget ? 'Goal hit' : 'Ended early',
                          style: TextStyle(
                            color: completedTarget
                                ? const Color(0xFFFF4663)
                                : const Color(0xFFFF9A31),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  int get _goalHits =>
      _history.where((entry) => entry['completedTarget'] == true).length;
}

class _FastingRingPainter extends CustomPainter {
  const _FastingRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 26;
    final basePaint = Paint()
      ..color = const Color(0xFFF0ECE7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFF6880),
          Color(0xFFFF3D5C),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    final startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      activePaint,
    );

    final tickPaint = Paint()
      ..color = const Color(0xFFDAD2CC)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 24; i++) {
      final angle = startAngle + ((2 * math.pi) / 24) * i;
      final outer = Offset(
        center.dx + math.cos(angle) * (radius - 10),
        center.dy + math.sin(angle) * (radius - 10),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 18),
        center.dy + math.sin(angle) * (radius - 18),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FastingRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
