import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class FastingTimerScreen extends StatefulWidget {
  const FastingTimerScreen({super.key});

  @override
  State<FastingTimerScreen> createState() => _FastingTimerScreenState();
}

class _FastingTimerScreenState extends State<FastingTimerScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<int> _fastingPlans = const [12, 14, 16, 18, 20, 24];

  Timer? _timer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fastingSubscription;
  int _selectedHours = 16;
  DateTime? _startTime;
  DateTime? _endTime;
  bool _isLoading = true;
  int _lastOngoingNotificationMinute = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFastingState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fastingSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  String get _userId =>
      AuthService.instance.currentSession?.id.toString() ?? '';

  DocumentReference<Map<String, dynamic>> get _fastingRef => _firestore
      .collection('users')
      .doc(_userId)
      .collection('wellness')
      .doc('fasting');

  CollectionReference<Map<String, dynamic>> get _historyRef =>
      _fastingRef.collection('history');

  Future<void> _loadFastingState() async {
    if (_userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _startTime = null;
          _endTime = null;
        });
      }
      return;
    }

    try {
      final snapshot = await _fastingRef.get();
      await _applyFastingData(snapshot.data());
      _listenToFastingState();
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

  void _listenToFastingState() {
    if (_userId.isEmpty) return;
    _fastingSubscription?.cancel();
    _fastingSubscription = _fastingRef.snapshots().listen(
      (snapshot) async {
        if (!mounted) return;
        await _applyFastingData(snapshot.data());
      },
      onError: (error) {
        debugPrint('Failed to listen to fasting state: $error');
      },
    );
  }

  Future<void> _applyFastingData(Map<String, dynamic>? data) async {
    if (!mounted) return;

    final nextSelectedHours = (data?['targetHours'] as num?)?.toInt() ?? 16;
    final nextStart = (data?['startTime'] as Timestamp?)?.toDate();
    final nextEnd = (data?['endTime'] as Timestamp?)?.toDate();

    setState(() {
      _selectedHours = nextSelectedHours;
      _startTime = nextStart;
      _endTime = nextEnd;
    });

    if (_startTime != null && _endTime != null) {
      await _syncFastingNotifications();
      _startTicker();
    } else {
      _timer?.cancel();
      await _clearFastingNotifications();
      _lastOngoingNotificationMinute = -1;
    }
  }

  Future<void> _startFast() async {
    final now = DateTime.now();
    final end = now.add(Duration(hours: _selectedHours));

    try {
      await _fastingRef.set({
        'targetHours': _selectedHours,
        'startTime': Timestamp.fromDate(now),
        'endTime': Timestamp.fromDate(end),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _startTime = now;
        _endTime = end;
      });
      _startTicker();
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
      if (startedAt != null) {
        final durationHours = finishedAt.difference(startedAt).inMinutes / 60.0;
        await _historyRef.add({
          'targetHours': _selectedHours,
          'startTime': Timestamp.fromDate(startedAt),
          'plannedEndTime':
              plannedEnd == null ? null : Timestamp.fromDate(plannedEnd),
          'finishedAt': Timestamp.fromDate(finishedAt),
          'completedHours': double.parse(durationHours.toStringAsFixed(2)),
          'completedTarget':
              plannedEnd != null && !finishedAt.isBefore(plannedEnd),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _fastingRef.set({
        'targetHours': _selectedHours,
        'startTime': null,
        'endTime': null,
        'lastCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _timer?.cancel();
      await _clearFastingNotifications();
      _lastOngoingNotificationMinute = -1;
      setState(() {
        _startTime = null;
        _endTime = null;
      });
    } catch (error) {
      debugPrint('Failed to end fasting timer: $error');
      _showSnackBar('Failed to end fasting timer.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadFastingState());
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
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
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
    final titleColor =
        isActive ? const Color(0xFF2B2826) : const Color(0xFF514A45);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  color: const Color(0xFFFFEEF2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isActive ? 'Fast in progress' : 'Ready to fast',
                  style: const TextStyle(
                    color: Color(0xFFFF4663),
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
                  backgroundColor: const Color(0xFFF7F0EA),
                  foregroundColor: const Color(0xFF3B332F),
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isActive
                          ? DateFormat('MMM d, hh:mm a').format(_endTime!)
                          : '$_selectedHours hour fasting window',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF35302C),
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
                      : const Color(0xFF1B1B1B).withValues(alpha: 0.12),
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
                  color: isActive
                      ? const Color(0xFFFF4663)
                      : const Color(0xFF2D2A28),
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
    return Material(
      color: Colors.white,
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
                  color: const Color(0xFFF8F5F0),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: const Color(0xFF4B4340)),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanSection(bool isActive) {
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
          const Text(
            'Fasting Plans',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            isActive
                ? 'Plan stays locked while your current fast is running.'
                : 'Pick the fasting window that fits your day.',
            style: const TextStyle(color: Colors.black54),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
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
          const Text(
            'Achievement Medals',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Unlock medals as you complete more fasting goals.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _historyRef
                .orderBy('finishedAt', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final goalHits = docs.where((doc) {
                return (doc.data()['completedTarget'] as bool?) ?? false;
              }).length;

              return Row(
                children: [
                  Expanded(
                    child: _achievementMedal(
                      title: 'Bronze',
                      subtitle: '3 goal hits',
                      icon: Icons.workspace_premium_rounded,
                      color: const Color(0xFFC78A55),
                      unlocked: goalHits >= 3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _achievementMedal(
                      title: 'Silver',
                      subtitle: '7 goal hits',
                      icon: Icons.military_tech_rounded,
                      color: const Color(0xFF98A3B4),
                      unlocked: goalHits >= 7,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _achievementMedal(
                      title: 'Gold',
                      subtitle: '15 goal hits',
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFFFFB52E),
                      unlocked: goalHits >= 15,
                    ),
                  ),
                ],
              );
            },
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/fastingReports'),
                child: const Text('View reports'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _historyRef
                .orderBy('finishedAt', descending: true)
                .limit(6)
                .snapshots(),
            builder: (context, snapshot) {
              final history = snapshot.data?.docs ?? [];

              if (history.isEmpty) {
                return Container(
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
                );
              }

              return Column(
                children: history.map((doc) {
                  final data = doc.data();
                  final targetHours =
                      (data['targetHours'] as num?)?.toInt() ?? 0;
                  final completedHours = (data['completedHours'] as num?) ?? 0;
                  final completedTarget =
                      (data['completedTarget'] as bool?) ?? false;
                  final finishedAt =
                      (data['finishedAt'] as Timestamp?)?.toDate();

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
              );
            },
          ),
        ],
      ),
    );
  }
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
