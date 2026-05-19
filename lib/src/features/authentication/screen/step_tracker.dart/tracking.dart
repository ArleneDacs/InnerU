import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/step_goal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, this.title = ''});

  final String title;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const Color _backgroundColor = Color(0xFFF7F4EE);
  static const Color _surfaceColor = Colors.white;
  static const Color _softSurfaceColor = Color(0xFFFCF5EA);
  static const Color _softGreenSurfaceColor = Color(0xFFF8FAF5);
  static const Color _primaryColor = Color(0xFF90A17D);
  static const Color _primaryDarkColor = Color(0xFF4D6A45);
  static const Color _secondaryColor = Color(0xFFCE8F5A);
  static const Color _textPrimaryColor = Color(0xFF243126);
  static const Color _textSecondaryColor = Color(0xFF6D7668);
  static const Color _borderColor = Color(0xFFE8E1D5);
  static const Color _ringTrackColor = Color(0xFFDDE7D6);
  static const Color _calorieTrackColor = Color(0xFFF0E1CC);
  static const Color _shadowColor = Color(0x12000000);
  static const double _strideMetersPerStep = 0.67;
  static const double _kcalPerStep = 0.04;
  static const int _defaultStepGoal = 5000;
  static const int _defaultCalorieGoal = 2000;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isLoadingHistoryMonth = false;
  bool _isSavingCalorieGoal = false;
  String? _errorMessage;
  List<_DayStepSummary> _weekSummaries = const [];
  List<_DayStepSummary> _historyMonthSummaries = const [];
  int _selectedDayIndex = 0;
  DateTime _historyMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _selectedHistoryDateKey =
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  _DayStepSummary? get _selectedSummary {
    if (_weekSummaries.isEmpty) return null;
    return _weekSummaries[_safeSelectedDayIndex(_weekSummaries.length)];
  }

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = DateTime.now().weekday - 1;
    _loadWeeklySummary();
  }

  Future<void> _loadWeeklySummary() async {
    final context = await _resolveLoadContext();
    if (context == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingHistoryMonth = false;
        _weekSummaries = const [];
        _historyMonthSummaries = const [];
        _errorMessage = 'Sign in to view your steps history.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final weekStart = _startOfWeekMonday(context.today);
      final weekDates = List.generate(
        7,
        (index) => weekStart.add(Duration(days: index)),
      );
      final monthDates = _historyCalendarDatesForMonth(_historyMonth);

      final results = await Future.wait<List<_DayStepSummary>>([
        _loadSummariesForDates(context, weekDates),
        _loadSummariesForDates(context, monthDates),
      ]);

      if (!mounted) return;
      setState(() {
        _weekSummaries = results[0];
        _historyMonthSummaries = results[1];
        _selectedDayIndex = _safeSelectedDayIndex(results[0].length);
        _selectedHistoryDateKey =
            _historySelectionForMonth(_historyMonth, context.today);
        _isLoading = false;
        _isLoadingHistoryMonth = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingHistoryMonth = false;
        _errorMessage = 'Unable to load your step summary right now.';
      });
    }
  }

  Future<_StepLoadContext?> _resolveLoadContext() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final cachedGoal = prefs.getInt('daily_step_goal_$userId');
    final localTodaySteps = prefs.getInt('saved_steps') ?? 0;
    var resolvedStepGoal =
        cachedGoal != null && cachedGoal > 0 ? cachedGoal : _defaultStepGoal;

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final remoteGoal = _readInt(userDoc.data()?['dailyStepGoal']);
      if (remoteGoal != null && remoteGoal > 0) {
        resolvedStepGoal = remoteGoal;
      }
    } catch (_) {
      // Keep the cached goal if Firestore is temporarily unavailable.
    }

    return _StepLoadContext(
      userId: userId,
      today: DateUtils.dateOnly(DateTime.now()),
      todaySteps: localTodaySteps,
      fallbackStepGoal: resolvedStepGoal,
    );
  }

  Future<List<_DayStepSummary>> _loadSummariesForDates(
    _StepLoadContext context,
    List<DateTime> dates,
  ) {
    return Future.wait(
      dates.map(
        (date) => _loadDaySummary(
          userId: context.userId,
          date: date,
          today: context.today,
          todaySteps: context.todaySteps,
          fallbackStepGoal: context.fallbackStepGoal,
        ),
      ),
    );
  }

  Future<void> _loadHistoryMonth(DateTime month) async {
    final context = await _resolveLoadContext();
    if (context == null) return;

    final targetMonth = _startOfMonth(month);
    if (mounted) {
      setState(() {
        _isLoadingHistoryMonth = true;
      });
    }

    try {
      final summaries = await _loadSummariesForDates(
        context,
        _historyCalendarDatesForMonth(targetMonth),
      );

      if (!mounted) return;
      setState(() {
        _historyMonth = targetMonth;
        _historyMonthSummaries = summaries;
        _selectedHistoryDateKey =
            _historySelectionForMonth(targetMonth, context.today);
        _isLoadingHistoryMonth = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistoryMonth = false;
      });
      _showSnackBar('Unable to load that month right now.');
    }
  }

  Future<_DayStepSummary> _loadDaySummary({
    required String userId,
    required DateTime date,
    required DateTime today,
    required int todaySteps,
    required int fallbackStepGoal,
  }) async {
    final dateKey = _dateKeyFor(date);

    final results = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
      _firestore.collection('dailytracker').doc('$userId-$dateKey').get(),
      _firestore
          .collection('steps')
          .doc(userId)
          .collection('tracking')
          .doc(dateKey)
          .get(),
      _firestore
          .collection('users')
          .doc(userId)
          .collection('calorie_logs')
          .doc(dateKey)
          .get(),
    ]);

    final trackerData = results[0].data();
    final historyData = results[1].data();
    final calorieData = results[2].data();

    var steps = _readInt(trackerData?['stepCount']) ??
        _readInt(historyData?['steps']) ??
        0;
    if (DateUtils.isSameDay(date, today)) {
      steps = math.max(steps, todaySteps);
    }

    final resolvedStepGoal =
        _readInt(trackerData?['stepGoal']) ?? fallbackStepGoal;
    final stepGoal = resolvedStepGoal > 0 ? resolvedStepGoal : fallbackStepGoal;

    final resolvedCalorieGoal =
        _readInt(calorieData?['dailyGoal']) ?? _defaultCalorieGoal;
    final calorieGoal =
        resolvedCalorieGoal > 0 ? resolvedCalorieGoal : _defaultCalorieGoal;
    final caloriesLogged = _readInt(calorieData?['totalCalories']) ?? 0;

    return _DayStepSummary(
      date: date,
      steps: steps,
      stepGoal: stepGoal,
      distanceKm: _distanceFromSteps(steps),
      estimatedBurnKcal: _estimatedBurnFromSteps(steps),
      calorieGoal: calorieGoal,
      caloriesLogged: caloriesLogged,
    );
  }

  String _dateKeyFor(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  DateTime _startOfMonth(DateTime date) {
    return DateTime(date.year, date.month);
  }

  DateTime _startOfWeekMonday(DateTime date) {
    final normalized = DateUtils.dateOnly(date);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  bool _isSameMonth(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month;
  }

  String _historyMonthLabel(DateTime month) {
    return DateFormat('MMMM yyyy').format(month);
  }

  List<DateTime> _historyCalendarDatesForMonth(DateTime month) {
    final monthStart = _startOfMonth(month);
    final gridStart = _startOfWeekMonday(monthStart);
    return List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
  }

  String _historySelectionForMonth(DateTime month, DateTime today) {
    final selectedDate = DateTime.tryParse(_selectedHistoryDateKey);
    if (selectedDate != null && _isSameMonth(selectedDate, month)) {
      return _dateKeyFor(selectedDate);
    }
    if (_isSameMonth(today, month)) {
      return _dateKeyFor(today);
    }
    return _dateKeyFor(_startOfMonth(month));
  }

  int _weekIndexForDate(DateTime date) {
    return _weekSummaries.indexWhere(
      (summary) => DateUtils.isSameDay(summary.date, date),
    );
  }

  int _safeSelectedDayIndex(int length) {
    if (length <= 0) return 0;
    final maxIndex = length - 1;
    if (_selectedDayIndex < 0) return 0;
    if (_selectedDayIndex > maxIndex) return maxIndex;
    return _selectedDayIndex;
  }

  int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double _distanceFromSteps(int steps) {
    return steps * _strideMetersPerStep / 1000;
  }

  int _estimatedBurnFromSteps(int steps) {
    return (steps * _kcalPerStep).round();
  }

  double _stepProgressFor(_DayStepSummary summary) {
    if (summary.stepGoal <= 0) return 0;
    return (summary.steps / summary.stepGoal).clamp(0.0, 1.0);
  }

  double _calorieProgressFor(_DayStepSummary summary) {
    if (summary.calorieGoal <= 0) return 0;
    return (summary.caloriesLogged / summary.calorieGoal).clamp(0.0, 1.0);
  }

  int _stepPercentFor(_DayStepSummary summary) {
    if (summary.stepGoal <= 0) return 0;
    return ((summary.steps / summary.stepGoal) * 100).round();
  }

  int _activeDaysCount() {
    return _weekSummaries.where((summary) => summary.steps > 0).length;
  }

  int _weeklyStepsTotal() {
    return _weekSummaries.fold<int>(0, (total, day) => total + day.steps);
  }

  int _weeklyAverageSteps() {
    if (_weekSummaries.isEmpty) return 0;
    return (_weeklyStepsTotal() / _weekSummaries.length).round();
  }

  String _formatSteps(int steps) {
    return NumberFormat.decimalPattern().format(steps);
  }

  String _formatKcal(int kcal) {
    return '${NumberFormat.decimalPattern().format(kcal)} kcal';
  }

  String _formatDistance(double distanceKm) {
    final decimals = distanceKm >= 10 ? 1 : 2;
    return '${distanceKm.toStringAsFixed(decimals)} km';
  }

  String _formatSelectedDate(DateTime date) {
    return DateFormat('EEEE, MMM d, y').format(date);
  }

  String _formatShortDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  String _weekdayLetter(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      case DateTime.sunday:
        return 'S';
      default:
        return '';
    }
  }

  String _historyLabel(_DayStepSummary summary) {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = DateUtils.dateOnly(summary.date);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(summary.date);
  }

  String _stepStatusText(_DayStepSummary summary) {
    if (summary.steps >= summary.stepGoal) {
      return 'Goal reached. Great work keeping your movement up.';
    }

    final remaining = math.max(summary.stepGoal - summary.steps, 0);
    return '${_formatSteps(remaining)} steps left to hit your goal.';
  }

  String _calorieStatusText(_DayStepSummary summary) {
    if (summary.caloriesLogged <= 0) {
      return 'No calories logged yet for this day.';
    }
    if (summary.caloriesLogged > summary.calorieGoal) {
      final over = summary.caloriesLogged - summary.calorieGoal;
      return 'Over goal by ${_formatKcal(over)}.';
    }
    final remaining = summary.calorieGoal - summary.caloriesLogged;
    return '${_formatKcal(remaining)} remaining in your calorie goal.';
  }

  void _reloadSoon() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadWeeklySummary();
    });
  }

  Future<void> _openStepGoalScreen([int? initialGoal]) async {
    final selectedSummary = _selectedSummary;
    final goal = initialGoal ?? selectedSummary?.stepGoal;
    if (goal == null) return;

    final updatedGoal = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => StepGoalScreen(initialGoal: goal),
      ),
    );

    if (updatedGoal != null && mounted) {
      _reloadSoon();
    }
  }

  Future<void> _editCalorieGoal([_DayStepSummary? summaryOverride]) async {
    final selectedSummary = summaryOverride ?? _selectedSummary;
    final userId = _auth.currentUser?.uid;
    if (selectedSummary == null || userId == null) return;

    var goalText = selectedSummary.calorieGoal.toString();

    final updatedGoal = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Daily Calorie Goal'),
          content: TextFormField(
            initialValue: goalText,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (value) => goalText = value,
            decoration: InputDecoration(
              hintText: 'Ex. 2200',
              helperText:
                  'This updates the goal for ${_formatShortDate(selectedSummary.date)}.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final goal = int.tryParse(goalText.trim());
                if (goal == null || goal <= 0) {
                  return;
                }
                Navigator.of(context).pop(goal);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updatedGoal == null) return;
    if (updatedGoal < 500 || updatedGoal > 10000) {
      _showSnackBar('Choose a calorie goal between 500 and 10,000 kcal.');
      return;
    }

    setState(() {
      _isSavingCalorieGoal = true;
    });

    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('calorie_logs')
          .doc(_dateKeyFor(selectedSummary.date))
          .set({
        'dailyGoal': updatedGoal,
        'date': _dateKeyFor(selectedSummary.date),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _reloadSoon();
      _showSnackBar('Calorie goal updated.');
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Failed to save calorie goal.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingCalorieGoal = false;
        });
      }
    }
  }

  Future<void> _openCalorieTracker() async {
    await Navigator.pushNamed(context, '/calorieTracker');
    if (mounted) {
      _reloadSoon();
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedSummary = _selectedSummary;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _primaryDarkColor,
        titleSpacing: 0,
        title: Text(
          selectedSummary == null
              ? 'Step Summary'
              : _formatSelectedDate(selectedSummary.date),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textPrimaryColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadWeeklySummary,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _backgroundColor,
              Color(0xFFF9F6F1),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _primaryDarkColor,
                ),
              )
            : _buildContent(selectedSummary),
      ),
    );
  }

  Widget _buildContent(_DayStepSummary? selectedSummary) {
    return RefreshIndicator(
      color: _primaryDarkColor,
      backgroundColor: _surfaceColor,
      onRefresh: _loadWeeklySummary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: selectedSummary == null
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroCard(selectedSummary),
                  const SizedBox(height: 18),
                  _buildStatsSection(selectedSummary),
                  const SizedBox(height: 18),
                  _buildCalorieGoalCard(selectedSummary),
                  const SizedBox(height: 18),
                  _buildWeekOverviewCard(),
                  const SizedBox(height: 18),
                  _buildHistorySection(),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _softGreenSurfaceColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_walk_rounded,
                size: 34,
                color: _primaryDarkColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _errorMessage ?? 'No step history yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textPrimaryColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Walk a little more, then pull down to refresh this page.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textSecondaryColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(_DayStepSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            _softGreenSurfaceColor,
            _softSurfaceColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final ring = _GoalRing(
            progress: _stepProgressFor(summary),
            size: compact ? 150 : 168,
            strokeWidth: compact ? 16 : 18,
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Daily summary',
                  style: TextStyle(
                    color: _primaryDarkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${_formatSteps(summary.steps)} steps',
                style: const TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_formatSteps(summary.stepGoal)} daily goal',
                style: const TextStyle(
                  color: _textSecondaryColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              _InlineInfoRow(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: _formatDistance(summary.distanceKm),
              ),
              const SizedBox(height: 10),
              _InlineInfoRow(
                icon: Icons.local_fire_department_rounded,
                label: 'Est. burn',
                value: _formatKcal(summary.estimatedBurnKcal),
              ),
              const SizedBox(height: 14),
              Text(
                _stepStatusText(summary),
                style: const TextStyle(
                  color: _textSecondaryColor,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.insights_rounded,
                    color: _secondaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatSelectedDate(summary.date),
                      style: const TextStyle(
                        color: _textPrimaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (compact) ...[
                Center(child: ring),
                const SizedBox(height: 18),
                details,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ring,
                    const SizedBox(width: 18),
                    Expanded(child: details),
                  ],
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ActionChip(
                    icon: Icons.flag_rounded,
                    label: 'Step Goal',
                    color: _secondaryColor,
                    onTap: _openStepGoalScreen,
                  ),
                  _ActionChip(
                    icon: Icons.local_fire_department_rounded,
                    label: _isSavingCalorieGoal ? 'Saving...' : 'Calorie Goal',
                    color: _primaryColor,
                    onTap: _isSavingCalorieGoal ? null : _editCalorieGoal,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsSection(_DayStepSummary summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Step Count',
                value: _formatSteps(summary.steps),
                helper: '${_stepPercentFor(summary)}% complete',
                icon: Icons.directions_walk_rounded,
                iconColor: _primaryDarkColor,
                tintColor: _softGreenSurfaceColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                label: 'Step Distance',
                value: _formatDistance(summary.distanceKm),
                helper: 'Estimated from steps',
                icon: Icons.straighten_rounded,
                iconColor: _secondaryColor,
                tintColor: _softSurfaceColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WideInsightCard(
          title: 'Estimated movement calories',
          value: _formatKcal(summary.estimatedBurnKcal),
          subtitle:
              'Approximate calories burned from walking based on your step count.',
          icon: Icons.local_fire_department_rounded,
          accentColor: _secondaryColor,
          backgroundColor: _surfaceColor,
        ),
      ],
    );
  }

  Widget _buildCalorieGoalCard(_DayStepSummary summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _softSurfaceColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: _secondaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calorie Goal',
                      style: TextStyle(
                        color: _textPrimaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Synced with your Calorie Tracker daily goal.',
                      style: TextStyle(
                        color: _textSecondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _isSavingCalorieGoal ? null : _editCalorieGoal,
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${_formatKcal(summary.caloriesLogged)} / ${_formatKcal(summary.calorieGoal)}',
            style: const TextStyle(
              color: _textPrimaryColor,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: _calorieProgressFor(summary),
              backgroundColor: _calorieTrackColor,
              valueColor: const AlwaysStoppedAnimation<Color>(_secondaryColor),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _calorieStatusText(summary),
            style: const TextStyle(
              color: _textSecondaryColor,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openCalorieTracker,
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryDarkColor,
              side: const BorderSide(color: _borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.restaurant_menu_rounded),
            label: const Text('Open Calorie Tracker'),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekOverviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_view_week_rounded, color: _primaryColor),
              SizedBox(width: 8),
              Text(
                'Weekly Overview',
                style: TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(_weekSummaries.length, (index) {
              final summary = _weekSummaries[index];
              final isSelected = index == _selectedDayIndex;

              return Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDayIndex = index;
                    });
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _primaryDarkColor
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _weekdayLetter(summary.date),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : _textSecondaryColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _GoalRing(
                          progress: _stepProgressFor(summary),
                          size: 42,
                          strokeWidth: 7,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _OverviewChip(
                label: 'Weekly total',
                value: _formatSteps(_weeklyStepsTotal()),
              ),
              _OverviewChip(
                label: 'Daily average',
                value: _formatSteps(_weeklyAverageSteps()),
              ),
              _OverviewChip(
                label: 'Active days',
                value: '${_activeDaysCount()}/7',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final history = _historyMonthSummaries;
    final today = DateUtils.dateOnly(DateTime.now());
    final currentMonth = _startOfMonth(today);
    final visibleMonth = _startOfMonth(_historyMonth);
    final canGoNext = visibleMonth.isBefore(currentMonth);
    final historyByDate = {
      for (final summary in history) _dateKeyFor(summary.date): summary,
    };
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final gridDates = history.isEmpty
        ? _historyCalendarDatesForMonth(visibleMonth)
        : history.map((summary) => summary.date).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _borderColor),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'History',
                style: TextStyle(
                  color: _textPrimaryColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _isLoadingHistoryMonth
                    ? null
                    : () => _loadHistoryMonth(
                          DateTime(visibleMonth.year, visibleMonth.month - 1),
                        ),
                icon: const Icon(Icons.chevron_left_rounded),
                visualDensity: VisualDensity.compact,
                color: _primaryDarkColor,
              ),
              Text(
                _historyMonthLabel(visibleMonth),
                style: const TextStyle(
                  color: _textSecondaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: !_isLoadingHistoryMonth && canGoNext
                    ? () => _loadHistoryMonth(
                          DateTime(visibleMonth.year, visibleMonth.month + 1),
                        )
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                visualDensity: VisualDensity.compact,
                color: _primaryDarkColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a date to open that day\'s steps, distance, calories, and goals.',
            style: TextStyle(
              color: _textSecondaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: weekdayLabels
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: _textSecondaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          if (_isLoadingHistoryMonth)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(color: _primaryDarkColor),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: gridDates.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 76,
              ),
              itemBuilder: (context, index) {
                final date = gridDates[index];
                final key = _dateKeyFor(date);
                final summary = historyByDate[key];
                final isSelected = key == _selectedHistoryDateKey;
                final isToday = DateUtils.isSameDay(date, today);
                final isFuture = DateUtils.dateOnly(date).isAfter(today);
                final isInMonth = _isSameMonth(date, visibleMonth);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: isFuture || summary == null
                        ? null
                        : () async {
                            final weekIndex = _weekIndexForDate(summary.date);
                            setState(() {
                              _selectedHistoryDateKey = key;
                              if (weekIndex != -1) {
                                _selectedDayIndex = weekIndex;
                              }
                            });
                            await _showHistoryDayDetails(summary);
                          },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _softGreenSurfaceColor
                            : !isInMonth
                                ? const Color(0xFFF3F0EA)
                                : isFuture
                                    ? const Color(0xFFF3F0EA)
                                    : _softSurfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? _primaryColor
                              : isToday
                                  ? _primaryDarkColor
                                  : Colors.transparent,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                color: !isInMonth || isFuture
                                    ? Colors.black38
                                    : _textPrimaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: summary != null &&
                                        summary.steps > 0 &&
                                        !isFuture
                                    ? _primaryColor
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 10,
                              child: isToday
                                  ? const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Today',
                                        style: TextStyle(
                                          color: _primaryDarkColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            if (isToday) const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showHistoryDayDetails(
    _DayStepSummary summary,
  ) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        Widget statusCard({
          required IconData icon,
          required String title,
          required String message,
          required Color backgroundColor,
        }) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: _primaryDarkColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _textPrimaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: const TextStyle(
                          color: _textSecondaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return FractionallySizedBox(
          heightFactor: 0.78,
          child: Container(
            decoration: const BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatSelectedDate(summary.date),
                                style: const TextStyle(
                                  color: _textPrimaryColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_historyLabel(summary)} • ${_formatSteps(summary.steps)} steps logged',
                                style: const TextStyle(
                                  color: _textSecondaryColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _softGreenSurfaceColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          _GoalRing(
                            progress: _stepProgressFor(summary),
                            size: 92,
                            strokeWidth: 11,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_stepPercentFor(summary)}% of goal',
                                  style: const TextStyle(
                                    color: _primaryDarkColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Goal ${_formatSteps(summary.stepGoal)} steps',
                                  style: const TextStyle(
                                    color: _textSecondaryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _stepStatusText(summary),
                                  style: const TextStyle(
                                    color: _textPrimaryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'Distance',
                            value: _formatDistance(summary.distanceKm),
                            helper: 'Walked that day',
                            icon: Icons.route_rounded,
                            iconColor: _primaryDarkColor,
                            tintColor: _softGreenSurfaceColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            label: 'Burn',
                            value: _formatKcal(summary.estimatedBurnKcal),
                            helper: 'Estimated movement calories',
                            icon: Icons.local_fire_department_rounded,
                            iconColor: _secondaryColor,
                            tintColor: _softSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'Calories Logged',
                            value: _formatKcal(summary.caloriesLogged),
                            helper: 'Food intake for the day',
                            icon: Icons.restaurant_menu_rounded,
                            iconColor: _secondaryColor,
                            tintColor: _softSurfaceColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            label: 'Calorie Goal',
                            value: _formatKcal(summary.calorieGoal),
                            helper: 'Daily intake target',
                            icon: Icons.flag_rounded,
                            iconColor: _primaryDarkColor,
                            tintColor: _softGreenSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    statusCard(
                      icon: Icons.directions_walk_rounded,
                      title: 'Step Status',
                      message: _stepStatusText(summary),
                      backgroundColor: _softGreenSurfaceColor,
                    ),
                    const SizedBox(height: 12),
                    statusCard(
                      icon: Icons.restaurant_rounded,
                      title: 'Calorie Status',
                      message: _calorieStatusText(summary),
                      backgroundColor: _softSurfaceColor,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ActionChip(
                          icon: Icons.flag_rounded,
                          label: 'Step Goal',
                          color: _primaryDarkColor,
                          onTap: () {
                            Navigator.pop(context);
                            _openStepGoalScreen(summary.stepGoal);
                          },
                        ),
                        _ActionChip(
                          icon: Icons.local_fire_department_rounded,
                          label: 'Calorie Goal',
                          color: _secondaryColor,
                          onTap: () {
                            Navigator.pop(context);
                            _editCalorieGoal(summary);
                          },
                        ),
                        _ActionChip(
                          icon: Icons.restaurant_menu_rounded,
                          label: 'Open Calories',
                          color: _primaryDarkColor,
                          onTap: () {
                            Navigator.pop(context);
                            _openCalorieTracker();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.progress,
    required this.size,
    required this.strokeWidth,
  });

  final double progress;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _GoalRingPainter(
              progress: progress,
              strokeWidth: strokeWidth,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  color: _TrackingScreenState._primaryDarkColor,
                  fontSize: size >= 150 ? 24 : 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (size >= 150)
                const Text(
                  'goal',
                  style: TextStyle(
                    color: _TrackingScreenState._textSecondaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({
    required this.progress,
    required this.strokeWidth,
  });

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final clampedProgress = progress.clamp(0.0, 1.0);

    final trackPaint = Paint()
      ..color = _TrackingScreenState._ringTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = _TrackingScreenState._primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final capPaint = Paint()
      ..color = _TrackingScreenState._secondaryColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, trackPaint);

    if (clampedProgress <= 0) {
      return;
    }

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clampedProgress,
      false,
      progressPaint,
    );

    final endAngle = (-math.pi / 2) + (2 * math.pi * clampedProgress);
    final capOffset = Offset(
      center.dx + math.cos(endAngle) * radius,
      center.dy + math.sin(endAngle) * radius,
    );
    canvas.drawCircle(capOffset, strokeWidth * 0.36, capPaint);
  }

  @override
  bool shouldRepaint(covariant _GoalRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _InlineInfoRow extends StatelessWidget {
  const _InlineInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _TrackingScreenState._primaryDarkColor),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            color: _TrackingScreenState._textSecondaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: _TrackingScreenState._textPrimaryColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _TrackingScreenState._borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _TrackingScreenState._textPrimaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.iconColor,
    required this.tintColor,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color iconColor;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _TrackingScreenState._surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TrackingScreenState._borderColor),
        boxShadow: const [
          BoxShadow(
            color: _TrackingScreenState._shadowColor,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: _TrackingScreenState._textSecondaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: _TrackingScreenState._textPrimaryColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            helper,
            style: const TextStyle(
              color: _TrackingScreenState._textSecondaryColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideInsightCard extends StatelessWidget {
  const _WideInsightCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _TrackingScreenState._borderColor),
        boxShadow: const [
          BoxShadow(
            color: _TrackingScreenState._shadowColor,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _TrackingScreenState._softSurfaceColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _TrackingScreenState._textSecondaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: _TrackingScreenState._textPrimaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _TrackingScreenState._textSecondaryColor,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _TrackingScreenState._softGreenSurfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _TrackingScreenState._textSecondaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _TrackingScreenState._textPrimaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayStepSummary {
  const _DayStepSummary({
    required this.date,
    required this.steps,
    required this.stepGoal,
    required this.distanceKm,
    required this.estimatedBurnKcal,
    required this.calorieGoal,
    required this.caloriesLogged,
  });

  final DateTime date;
  final int steps;
  final int stepGoal;
  final double distanceKm;
  final int estimatedBurnKcal;
  final int calorieGoal;
  final int caloriesLogged;
}

class _StepLoadContext {
  const _StepLoadContext({
    required this.userId,
    required this.today,
    required this.todaySteps,
    required this.fallbackStepGoal,
  });

  final String userId;
  final DateTime today;
  final int todaySteps;
  final int fallbackStepGoal;
}
