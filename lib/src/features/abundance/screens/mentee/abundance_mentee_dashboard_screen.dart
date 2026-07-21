import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/dashboard/emotion_tracker.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/coach_directory_api_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class AbundanceMenteeDashboardScreen extends StatefulWidget {
  const AbundanceMenteeDashboardScreen({
    super.key,
    this.initialCompanyTheme,
    this.service,
  });

  final CompanyThemeData? initialCompanyTheme;
  final GoalsService? service;

  @override
  State<AbundanceMenteeDashboardScreen> createState() =>
      _AbundanceMenteeDashboardScreenState();
}

class _AbundanceMenteeDashboardScreenState
    extends State<AbundanceMenteeDashboardScreen> {
  late final GoalsService _service;
  late Future<_DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalsService();
    _dashboardFuture = _loadDashboard();
  }

  Future<void> _reloadDashboard() async {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
    await _dashboardFuture;
  }

  Future<_DashboardData> _loadDashboard() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return _DashboardData.denied(theme: CompanyThemeData.standard);
    }

    final userId = session.id.toString();
    final userData = await UserService.getUserData();
    final membershipData = CompanyMembershipService.fromUserData(userData);
    final activeMembership = membershipData.activeMembership;
    final theme = widget.initialCompanyTheme ??
        await CompanyThemeService.resolveForUser(userId);

    final companyName = (activeMembership?.name.isNotEmpty == true)
        ? activeMembership!.name
        : theme.companyName;
    final companyCode = (activeMembership?.code.isNotEmpty == true)
        ? activeMembership!.code
        : theme.companyCode;
    final isAllowed = _isAbundance12Company(
      name: companyName,
      code: companyCode,
    );

    final goals = await _service.watchGoals(userId).first;
    final trackerDocs = await DailyTrackerApiService.instance.fetchHistory();
    final emotionDocs = await EmotionService().fetchHistory();

    final coach = await _loadCoachProfile(
      userData: userData,
    );

    final displayName = _displayNameFrom(userData, fallback: session.email);
    final joinedAt = _dateFrom(
          userData['createdAt'],
        ) ??
        _dateFrom(userData['joinedAt']) ??
        DateTime.now().subtract(const Duration(days: 365));

    final dailyLogs = _buildDailyLogs(trackerDocs);
    final emotionLogs = _buildEmotionLogs(emotionDocs);

    return _DashboardData(
      allowed: isAllowed,
      theme: theme,
      companyName: companyName,
      companyCode: companyCode,
      displayName: displayName,
      profilePic: _stringValue(userData['profilePic']),
      coach: coach,
      joinedAt: joinedAt,
      goals: goals,
      dailyLogs: dailyLogs,
      emotionLogs: emotionLogs,
      userId: userId,
    );
  }

  Future<_CoachProfile?> _loadCoachProfile({
    required Map<String, dynamic> userData,
  }) async {
    final coachIds = <String>[
      _stringValue(userData['coachId']),
      ...List<String>.from(userData['coachIds'] as List? ?? const <String>[]),
    ].where((id) => id.trim().isNotEmpty).toList();

    if (coachIds.isEmpty) {
      return null;
    }

    final coachId = coachIds.first;
    final coaches = await CoachDirectoryApiService.instance.fetchCoaches();
    for (final coach in coaches) {
      if (coach.id == coachId) {
        return _CoachProfile(
          id: coach.id,
          name: coach.name.isNotEmpty ? coach.name : 'Coach',
          headline: 'Your support coach',
          profilePic: coach.profilePic ?? '',
        );
      }
    }

    return null;
  }

  List<_DailyLog> _buildDailyLogs(
    List<Map<String, dynamic>> docs,
  ) {
    final byDay = <String, _DailyLog>{};
    for (final data in docs) {
      final day = _dayKeyFrom(data);
      final timestamp = _dateFrom(
            data['lastUpdated'],
          ) ??
          _dateFrom(data['updatedAt']) ??
          _dateFrom(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final completed = _countCheckedTasks(data);
      final total = _taskFields.length;
      final candidate = _DailyLog(
        dayKey: day,
        completedTasks: completed,
        totalTasks: total,
        updatedAt: timestamp,
      );

      final existing = byDay[day];
      if (existing == null || candidate.updatedAt.isAfter(existing.updatedAt)) {
        byDay[day] = candidate;
      }
    }

    final logs = byDay.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return logs;
  }

  List<_EmotionLog> _buildEmotionLogs(
    List<Map<String, dynamic>> docs,
  ) {
    final byDay = <String, _EmotionLog>{};
    for (final data in docs) {
      final day = _stringValue(data['date']).trim().isNotEmpty
          ? _stringValue(data['date']).trim()
          : isoDay(
              _dateFrom(data['lastLoggedAt']) ??
                  _dateFrom(data['updatedAt']) ??
                  _dateFrom(data['createdAt']) ??
                  DateTime.now(),
            );
      final timestamp = _dateFrom(
            data['lastLoggedAt'],
          ) ??
          _dateFrom(data['updatedAt']) ??
          _dateFrom(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final emotion = _stringValue(data['emotion']).trim().toLowerCase();
      if (emotion.isEmpty) continue;
      final candidate = _EmotionLog(
        dayKey: day,
        emotion: emotion,
        loggedAt: timestamp,
      );

      final existing = byDay[day];
      if (existing == null || candidate.loggedAt.isAfter(existing.loggedAt)) {
        byDay[day] = candidate;
      }
    }

    final logs = byDay.values.toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return logs;
  }

  int _countCheckedTasks(Map<String, dynamic> data) {
    var completed = 0;
    for (final field in _taskFields) {
      if (data[field] == true) completed += 1;
    }
    return completed;
  }

  String _dayKeyFrom(Map<String, dynamic> data) {
    final raw = data['date'] ??
        data['lastUpdated'] ??
        data['updatedAt'] ??
        data['createdAt'];
    final dt = _dateFrom(raw) ?? DateTime.now();
    return isoDay(dt);
  }

  String _displayNameFrom(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final firstName = _stringValue(data['firstName']).trim();
    final lastName = _stringValue(data['lastName']).trim();
    final fullName = _stringValue(data['fullName']).trim();
    final username = _stringValue(data['username']).trim();
    final email = _stringValue(data['email']).trim();

    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
    }
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email.split('@').first;
    return fallback;
  }

  String _stringValue(dynamic value) => value is String ? value.trim() : '';

  DateTime? _dateFrom(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  bool _isAbundance12Company({
    String name = '',
    String code = '',
  }) {
    final normalizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedCode = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalizedName.contains('abundance12') ||
        (normalizedName.contains('abundance') && normalizedName.contains('12')) ||
        normalizedCode.contains('ABUNDANCE12') ||
        normalizedCode.contains('ABUND12') ||
        normalizedCode == 'A12' ||
        normalizedCode.startsWith('AB12');
  }

  Future<void> _openGoalForm() async {
    final data = await _dashboardFuture;
    if (!mounted) return;
    if (!data.allowed) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalFormScreen(
          service: _service,
          uid: data.userId,
        ),
      ),
    );
    if (mounted) await _reloadDashboard();
  }

  Future<void> _openGoalDetail(GoalSummary goal) async {
    final data = await _dashboardFuture;
    if (!mounted) return;
    if (!data.allowed) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(
          goalId: goal.id,
          service: _service,
          uid: data.userId,
        ),
      ),
    );
    if (mounted) await _reloadDashboard();
  }

  Future<void> _openNamedRoute(String routeName) async {
    await Navigator.of(context).pushNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!;
        if (!data.allowed) {
          return _AccessDeniedView(theme: data.theme);
        }

        final goals = data.goals;
        final scoreGoals = goals
            .map(
              (goal) => ScorableGoal(
                status: goal.status,
                progress: goal.progress,
                category: goal.category,
                goalType: goal.goalType,
                targetValue: goal.targetValue,
                currentValue: goal.currentValue,
              ),
            )
            .toList();
        final completionDays = _completionDaysFrom(data.dailyLogs);
        final checkInDays = data.emotionLogs.map((log) => log.dayKey).toList();
        final score = computeUserScore(
          UserScoreInputs(
            userId: data.userId,
            joinedAt: data.joinedAt,
            goals: scoreGoals,
            completionDays: completionDays,
            checkInDays: checkInDays,
            activeCoreTaskCount: _taskFields.length,
          ),
          asOf: DateTime.now(),
        );
        final goalTotalScore = score.goalScore;
        final rank = rankForPercent(goalTotalScore);
        final categoryStats = _buildCategoryStats(goals, score);
        final upcomingDeadlines = goals
            .where((goal) => goal.status != GoalStatus.completed)
            .where((goal) => goal.status != GoalStatus.abandoned)
            .toList()
          ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
        final recentCheckIns = data.emotionLogs.take(5).toList();
        final achievements = _buildAchievements(score, goals);
        final momentumPoints = _buildMomentumPoints(data);
        final todayLog = data.dailyLogs.isNotEmpty
            ? data.dailyLogs.lastWhere(
                (log) => log.dayKey == isoDay(DateTime.now()),
                orElse: () => data.dailyLogs.last,
              )
            : null;
        final todayEmotion = data.emotionLogs.firstWhere(
          (log) => log.dayKey == isoDay(DateTime.now()),
          orElse: () => _EmotionLog(
            dayKey: '',
            emotion: '',
            loggedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );

        return Theme(
          data: AppTheme.company(data.theme),
          child: Scaffold(
            backgroundColor: data.theme.backgroundColor,
            appBar: AppBar(
              backgroundColor: data.theme.surfaceColor,
              foregroundColor: data.theme.inkColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: const Text('Abundance Dashboard'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => unawaited(_reloadDashboard()),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) async {
                    switch (value) {
                      case 'goals':
                        await _openNamedRoute('/goalsHub');
                        break;
                      case 'checkin':
                        await _openNamedRoute('/emotionScreen');
                        break;
                      case 'rank':
                        await _openNamedRoute('/leaderboard');
                        break;
                      case 'tasks':
                        await _openNamedRoute('/userprogress');
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'goals', child: Text('Goals')),
                    PopupMenuItem(value: 'checkin', child: Text('Check in')),
                    PopupMenuItem(value: 'rank', child: Text('Leaderboard')),
                    PopupMenuItem(value: 'tasks', child: Text('Core tasks')),
                  ],
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: _reloadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _HeroCard(
                    theme: data.theme,
                    companyName: data.companyName,
                    displayName: data.displayName,
                    companyCode: data.companyCode,
                    profilePic: data.profilePic,
                    goalTotalScore: goalTotalScore,
                    rank: rank,
                    currentStreak: score.currentStreak,
                    checkInRate: score.checkInRate,
                    todayTasksCompleted: todayLog?.completedTasks ?? 0,
                    todayTasksTotal: todayLog?.totalTasks ?? _taskFields.length,
                    todayEmotion: todayEmotion.emotion,
                  ),
                  const SizedBox(height: 18),
                  _QuickActionGrid(
                    theme: data.theme,
                    onGoals: () =>
                        unawaited(_openNamedRoute('/goalsHub')),
                    onCheckIn: () =>
                        unawaited(_openNamedRoute('/emotionScreen')),
                    onRank: () =>
                        unawaited(_openNamedRoute('/leaderboard')),
                    onTasks: () =>
                        unawaited(_openNamedRoute('/userprogress')),
                  ),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: 'Goals by category',
                    actionLabel: 'Open goals',
                    onAction: () =>
                        unawaited(_openNamedRoute('/goalsHub')),
                  ),
                  if (requiredGoalGaps(goals).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _MissingCategoryBanner(gaps: requiredGoalGaps(goals)),
                  ],
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 3
                          : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: GoalCategory.values.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: columns == 1 ? 2.3 : 1.55,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (context, index) {
                          final category = GoalCategory.values[index];
                          final stat = categoryStats[category]!;
                          return _CategoryCard(
                            theme: data.theme,
                            category: category,
                            totalGoals: stat.totalGoals,
                            completedGoals: stat.completedGoals,
                            score: stat.score,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumn = constraints.maxWidth >= 900;
                      final left = _DeadlinesCard(
                        theme: data.theme,
                        goals: upcomingDeadlines.take(5).toList(),
                        onGoalTap: _openGoalDetail,
                      );
                      final right = _CoachAndCheckInsCard(
                        theme: data.theme,
                        coach: data.coach,
                        recentCheckIns: recentCheckIns,
                        todayEmotion: todayEmotion.emotion,
                        onOpenMoodTracker: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const EmotionTrackerPage(),
                          ),
                        ),
                      );

                      if (twoColumn) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: 12),
                            Expanded(child: right),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          left,
                          const SizedBox(height: 12),
                          right,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: 'Personal analytics',
                    actionLabel: 'Refresh',
                    onAction: () => unawaited(_reloadDashboard()),
                  ),
                  const SizedBox(height: 10),
                  _AnalyticsCard(
                    theme: data.theme,
                    points: momentumPoints,
                  ),
                  const SizedBox(height: 18),
                  _SectionHeader(
                    title: 'Achievements',
                    actionLabel: 'Add goal',
                    onAction: () => unawaited(_openGoalForm()),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final achievement = achievements[index];
                        return _AchievementCard(
                          theme: data.theme,
                          achievement: achievement,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemCount: achievements.length,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => unawaited(_openGoalForm()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New goal'),
            ),
          ),
        );
      },
    );
  }

  List<String> _completionDaysFrom(List<_DailyLog> logs) {
    final days = <String>[];
    for (final log in logs) {
      for (var i = 0; i < log.completedTasks; i += 1) {
        days.add(log.dayKey);
      }
    }
    return days;
  }

  Map<GoalCategory, _CategoryStat> _buildCategoryStats(
    List<GoalSummary> goals,
    UserScore score,
  ) {
    final stats = <GoalCategory, _CategoryStat>{
      for (final category in GoalCategory.values)
        category: const _CategoryStat(totalGoals: 0, completedGoals: 0, score: 0),
    };

    for (final goal in goals) {
      final current = stats[goal.category]!;
      stats[goal.category] = _CategoryStat(
        totalGoals: current.totalGoals + 1,
        completedGoals: current.completedGoals +
            (goal.status == GoalStatus.completed ? 1 : 0),
        score: score.categories[goal.category] ?? 0,
      );
    }

    return stats;
  }

  List<_Achievement> _buildAchievements(UserScore score, List<GoalSummary> goals) {
    final completed = goals.where((goal) => goal.status == GoalStatus.completed).length;
    final hasAllCategories = requiredGoalGaps(goals).isEmpty;
    final hasAnyGoal = goals.isNotEmpty;
    final hasNoOverdue = goals.every((goal) => !goal.isOverdue);

    return [
      _Achievement(
        title: 'First goal',
        subtitle: 'A goal is on the board.',
        icon: Icons.flag_rounded,
        unlocked: hasAnyGoal,
      ),
      _Achievement(
        title: 'Balanced',
        subtitle: 'All three life areas are covered.',
        icon: Icons.balance_rounded,
        unlocked: hasAllCategories,
      ),
      _Achievement(
        title: 'Momentum',
        subtitle: 'Current streak of 3 days.',
        icon: Icons.local_fire_department_rounded,
        unlocked: score.currentStreak >= 3,
      ),
      _Achievement(
        title: 'Consistency',
        subtitle: 'Current streak of 7 days.',
        icon: Icons.trending_up_rounded,
        unlocked: score.currentStreak >= 7,
      ),
      _Achievement(
        title: 'Finisher',
        subtitle: '$completed completed goals.',
        icon: Icons.verified_rounded,
        unlocked: completed >= 3,
      ),
      _Achievement(
        title: 'Clear runway',
        subtitle: 'No overdue goals left behind.',
        icon: Icons.check_circle_rounded,
        unlocked: hasNoOverdue,
      ),
    ];
  }

  List<_MomentumPoint> _buildMomentumPoints(_DashboardData data) {
    final days = lastNDays(7);
    final trackerByDay = <String, _DailyLog>{for (final log in data.dailyLogs) log.dayKey: log};
    final checkInsByDay = <String, _EmotionLog>{
      for (final log in data.emotionLogs) log.dayKey: log,
    };
    return [
      for (final day in days)
        _MomentumPoint(
          label: DateFormat('E').format(day),
          value: _dailyMomentumScore(
            trackerByDay[isoDay(day)],
            checkInsByDay[isoDay(day)],
          ),
        ),
    ];
  }

  double _dailyMomentumScore(_DailyLog? log, _EmotionLog? emotion) {
    final taskScore = log == null || log.totalTasks == 0
        ? 0.0
        : (log.completedTasks / log.totalTasks) * 100;
    final checkInBonus = emotion == null ? 0.0 : 100.0;
    return (taskScore * 0.7) + (checkInBonus * 0.3);
  }
}

class _DashboardData {
  const _DashboardData({
    required this.allowed,
    required this.theme,
    required this.companyName,
    required this.companyCode,
    required this.displayName,
    required this.profilePic,
    required this.coach,
    required this.joinedAt,
    required this.goals,
    required this.dailyLogs,
    required this.emotionLogs,
    required this.userId,
  });

  _DashboardData.denied({required this.theme})
      : allowed = false,
        companyName = '',
        companyCode = '',
        displayName = '',
        profilePic = '',
        coach = null,
        joinedAt = DateTime.fromMillisecondsSinceEpoch(0),
        goals = const <GoalSummary>[],
        dailyLogs = const <_DailyLog>[],
        emotionLogs = const <_EmotionLog>[],
        userId = '';

  final bool allowed;
  final CompanyThemeData theme;
  final String companyName;
  final String companyCode;
  final String displayName;
  final String profilePic;
  final _CoachProfile? coach;
  final DateTime joinedAt;
  final List<GoalSummary> goals;
  final List<_DailyLog> dailyLogs;
  final List<_EmotionLog> emotionLogs;
  final String userId;
}

class _CoachProfile {
  const _CoachProfile({
    required this.id,
    required this.name,
    required this.headline,
    required this.profilePic,
  });

  final String id;
  final String name;
  final String headline;
  final String profilePic;
}

class _DailyLog {
  const _DailyLog({
    required this.dayKey,
    required this.completedTasks,
    required this.totalTasks,
    required this.updatedAt,
  });

  final String dayKey;
  final int completedTasks;
  final int totalTasks;
  final DateTime updatedAt;
}

class _EmotionLog {
  const _EmotionLog({
    required this.dayKey,
    required this.emotion,
    required this.loggedAt,
  });

  final String dayKey;
  final String emotion;
  final DateTime loggedAt;
}

class _CategoryStat {
  const _CategoryStat({
    required this.totalGoals,
    required this.completedGoals,
    required this.score,
  });

  final int totalGoals;
  final int completedGoals;
  final double score;
}

class _MomentumPoint {
  const _MomentumPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;
}

class _Achievement {
  const _Achievement({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.unlocked,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool unlocked;
}

class _AccessDeniedView extends StatelessWidget {
  const _AccessDeniedView({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                color: theme.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: theme.iconColor,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'A12 access only',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: theme.inkColor,
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This dashboard is reserved for Abundance 12 company members.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: theme.mutedInkColor,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.theme,
    required this.companyName,
    required this.displayName,
    required this.companyCode,
    required this.profilePic,
    required this.goalTotalScore,
    required this.rank,
    required this.currentStreak,
    required this.checkInRate,
    required this.todayTasksCompleted,
    required this.todayTasksTotal,
    required this.todayEmotion,
  });

  final CompanyThemeData theme;
  final String companyName;
  final String displayName;
  final String companyCode;
  final String profilePic;
  final double goalTotalScore;
  final GoalRank rank;
  final int currentStreak;
  final double checkInRate;
  final int todayTasksCompleted;
  final int todayTasksTotal;
  final String todayEmotion;

  @override
  Widget build(BuildContext context) {
    final rankLabel = '${rank.name} · ${rank.min}–${rank.max}%';
    final scoreColor = _scoreColor(goalTotalScore, theme);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.accentColor,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.black.withValues(alpha: 0.08),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  label: 'Abundance 12',
                  background: Colors.white.withValues(alpha: 0.18),
                  foreground: Colors.white,
                ),
                _Pill(
                  label: companyCode.isNotEmpty ? companyCode : companyName,
                  background: Colors.white.withValues(alpha: 0.18),
                  foreground: Colors.white,
                ),
                _Pill(
                  label: todayEmotion.isNotEmpty
                      ? '${todayEmotion[0].toUpperCase()}${todayEmotion.substring(1)} mood'
                      : 'No check-in yet',
                  background: Colors.white.withValues(alpha: 0.18),
                  foreground: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, $displayName',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your goals, check-ins, momentum and progress for today live here.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MiniMetric(
                            label: 'Current streak',
                            value: '$currentStreak days',
                          ),
                          _MiniMetric(
                            label: 'Today',
                            value:
                                '$todayTasksCompleted/$todayTasksTotal tasks',
                          ),
                          _MiniMetric(
                            label: 'Check-ins',
                            value: '${checkInRate.toStringAsFixed(0)}%',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    _ScoreRing(
                      score: goalTotalScore,
                      accent: scoreColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      rankLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _AvatarFrame(
                      profilePic: profilePic,
                      fallback: displayName,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.accent,
  });

  final double score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100).toDouble();
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: CircularProgressIndicator(
              value: clamped / 100,
              strokeWidth: 12,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  clamped.toStringAsFixed(0),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Goal score',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFrame extends StatelessWidget {
  const _AvatarFrame({
    required this.profilePic,
    required this.fallback,
  });

  final String profilePic;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      backgroundImage: profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
      child: profilePic.isNotEmpty
          ? null
          : Text(
              fallback.isNotEmpty ? fallback[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({
    required this.theme,
    required this.onGoals,
    required this.onCheckIn,
    required this.onRank,
    required this.onTasks,
  });

  final CompanyThemeData theme;
  final VoidCallback onGoals;
  final VoidCallback onCheckIn;
  final VoidCallback onRank;
  final VoidCallback onTasks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final actions = [
          _ActionSpec(
            title: 'Goals',
            subtitle: 'Open your goals hub',
            icon: Icons.flag_rounded,
            onTap: onGoals,
          ),
          _ActionSpec(
            title: 'Check in',
            subtitle: 'Log your mood',
            icon: Icons.edit_note_rounded,
            onTap: onCheckIn,
          ),
          _ActionSpec(
            title: 'Leaderboard',
            subtitle: 'See your rank',
            icon: Icons.emoji_events_rounded,
            onTap: onRank,
          ),
          _ActionSpec(
            title: 'Core tasks',
            subtitle: 'Today’s habits',
            icon: Icons.checklist_rounded,
            onTap: onTasks,
          ),
        ];

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 2 ? 1.8 : 2.5,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _ActionCard(theme: theme, action: action);
          },
        );
      },
    );
  }
}

class _ActionSpec {
  const _ActionSpec({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.theme,
    required this.action,
  });

  final CompanyThemeData theme;
  final _ActionSpec action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surfaceColor,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: action.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(action.icon, color: theme.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: theme.inkColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: theme.mutedInkColor,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _MissingCategoryBanner extends StatelessWidget {
  const _MissingCategoryBanner({required this.gaps});

  final List<GoalCategory> gaps;

  @override
  Widget build(BuildContext context) {
    final missing = gaps.map((category) => category.label.toLowerCase()).join(' or ');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(14),
      child: Text(
        'No $missing goal yet. Every category matters, and an empty one scores zero.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.red.shade700,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.theme,
    required this.category,
    required this.totalGoals,
    required this.completedGoals,
    required this.score,
  });

  final CompanyThemeData theme;
  final GoalCategory category;
  final int totalGoals;
  final int completedGoals;
  final double score;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.accent);
    final empty = totalGoals == 0;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: theme.inkColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Chip(
                label: Text(empty ? 'None set' : '$totalGoals goals'),
                visualDensity: VisualDensity.compact,
                backgroundColor: color.withValues(alpha: 0.1),
                side: BorderSide(color: color.withValues(alpha: 0.15)),
                labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${score.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: score / 100,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 10),
          Text(
            empty
                ? 'No goals here yet.'
                : '$completedGoals completed of $totalGoals goals.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: theme.mutedInkColor,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _DeadlinesCard extends StatelessWidget {
  const _DeadlinesCard({
    required this.theme,
    required this.goals,
    required this.onGoalTap,
  });

  final CompanyThemeData theme;
  final List<GoalSummary> goals;
  final Future<void> Function(GoalSummary goal) onGoalTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming deadlines',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (goals.isEmpty)
            Text(
              'Nothing due right now. You have room to keep building.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: theme.mutedInkColor,
                    height: 1.45,
                  ),
            )
          else
            Column(
              children: [
                for (final goal in goals.take(5)) ...[
                  _DeadlineTile(
                    goal: goal,
                    theme: theme,
                    onTap: () => onGoalTap(goal),
                  ),
                  if (goal != goals.take(5).last)
                    Divider(color: theme.mutedInkColor.withValues(alpha: 0.12)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({
    required this.goal,
    required this.theme,
    required this.onTap,
  });

  final GoalSummary goal;
  final CompanyThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final late = goal.isOverdue;
    final category = GoalCategory.fromCode(goal.category.code);
    final color = Color(category.accent);
    final dueText = goal.isOverdue
        ? 'Overdue by ${goal.daysUntilDue.abs()} days'
        : goal.daysUntilDue == 0
            ? 'Due today'
            : '${goal.daysUntilDue} days left';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                late ? Icons.warning_amber_rounded : Icons.calendar_month_rounded,
                color: late ? Colors.red : color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: theme.inkColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${category.label} · ${DateFormat.MMMd().format(goal.targetDate)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: theme.mutedInkColor,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: late
                    ? Colors.red.withValues(alpha: 0.08)
                    : theme.iconColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                dueText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: late ? Colors.red.shade700 : theme.iconColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachAndCheckInsCard extends StatelessWidget {
  const _CoachAndCheckInsCard({
    required this.theme,
    required this.coach,
    required this.recentCheckIns,
    required this.todayEmotion,
    required this.onOpenMoodTracker,
  });

  final CompanyThemeData theme;
  final _CoachProfile? coach;
  final List<_EmotionLog> recentCheckIns;
  final String todayEmotion;
  final VoidCallback onOpenMoodTracker;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach and check-ins',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (coach != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.iconColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.iconColor.withValues(alpha: 0.12),
                    backgroundImage:
                        coach!.profilePic.isNotEmpty ? NetworkImage(coach!.profilePic) : null,
                    child: coach!.profilePic.isEmpty
                        ? Text(
                            coach!.name.isNotEmpty ? coach!.name[0].toUpperCase() : 'C',
                            style: TextStyle(
                              color: theme.iconColor,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coach!.name,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: theme.inkColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          coach!.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: theme.mutedInkColor,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.iconColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.mood_rounded, color: theme.iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    todayEmotion.isNotEmpty
                        ? 'Today’s mood: ${todayEmotion[0].toUpperCase()}${todayEmotion.substring(1)}'
                        : 'No mood check-in yet today.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: theme.inkColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onOpenMoodTracker,
            style: TextButton.styleFrom(
              foregroundColor: theme.iconColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.mood_rounded, size: 18),
            label: Text(
              todayEmotion.isNotEmpty ? 'Open mood tracker' : 'Check in now',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Recent check-ins',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (recentCheckIns.isEmpty)
            Text(
              'No recent check-ins yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: theme.mutedInkColor,
                  ),
            )
          else
            Column(
              children: [
                for (final entry in recentCheckIns.take(5)) ...[
                  _CheckInTile(theme: theme, entry: entry),
                  if (entry != recentCheckIns.take(5).last)
                    Divider(color: theme.mutedInkColor.withValues(alpha: 0.12)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _CheckInTile extends StatelessWidget {
  const _CheckInTile({
    required this.theme,
    required this.entry,
  });

  final CompanyThemeData theme;
  final _EmotionLog entry;

  @override
  Widget build(BuildContext context) {
    final icon = _emotionIcon(entry.emotion);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.emotion[0].toUpperCase()}${entry.emotion.substring(1)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: theme.inkColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.dayKey,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: theme.mutedInkColor,
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

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.theme,
    required this.points,
  });

  final CompanyThemeData theme;
  final List<_MomentumPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(
      100.0,
      points.fold<double>(0, (total, point) => math.max(total, point.value + 10)),
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Momentum last 7 days',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'A gentle blend of daily task completion and check-ins.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: theme.mutedInkColor,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.mutedInkColor.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 25,
                      getTitlesWidget: (value, meta) {
                        if (value % 25 != 0) return const SizedBox.shrink();
                        return Text(
                          value.toInt().toString(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: theme.mutedInkColor,
                              ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            points[index].label,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: theme.mutedInkColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: theme.mutedInkColor.withValues(alpha: 0.12),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i += 1)
                        FlSpot(i.toDouble(), points[i].value),
                    ],
                    isCurved: true,
                    barWidth: 3,
                    color: theme.iconColor,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: theme.iconColor.withValues(alpha: 0.12),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => theme.surfaceColor,
                    getTooltipItems: (items) {
                      return items.map((item) {
                        return LineTooltipItem(
                          '${item.y.toDouble().toStringAsFixed(0)}%',
                          TextStyle(
                            color: theme.inkColor,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.theme,
    required this.achievement,
  });

  final CompanyThemeData theme;
  final _Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final color = achievement.unlocked ? theme.iconColor : theme.mutedInkColor;
    return Container(
      width: 162,
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withValues(alpha: achievement.unlocked ? 0.18 : 0.12),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(achievement.icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            achievement.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: theme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.subtitle,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: theme.mutedInkColor,
                  height: 1.35,
                ),
          ),
          const Spacer(),
          Chip(
            label: Text(achievement.unlocked ? 'Unlocked' : 'Locked'),
            labelStyle: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            visualDensity: VisualDensity.compact,
            backgroundColor: color.withValues(alpha: 0.08),
            side: BorderSide(color: color.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

Color _scoreColor(double score, CompanyThemeData theme) {
  if (score >= 80) return theme.iconColor;
  if (score >= 60) return theme.primaryColor;
  if (score >= 40) return const Color(0xFFCE8F5A);
  return const Color(0xFFC05A5A);
}

IconData _emotionIcon(String emotion) {
  switch (emotion.toLowerCase()) {
    case 'happy':
      return Icons.sentiment_satisfied_alt_rounded;
    case 'sad':
      return Icons.sentiment_dissatisfied_rounded;
    case 'angry':
      return Icons.local_fire_department_rounded;
    case 'neutral':
      return Icons.remove_circle_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

const List<String> _taskFields = <String>[
  'call',
  'steps',
  'exercise',
  'meditation',
  'learning',
  'addValue',
];
