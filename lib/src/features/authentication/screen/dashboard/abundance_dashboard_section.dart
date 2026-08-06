import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/coach_api_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/emotion_service.dart';
import 'package:selfcare_projects/src/services/leaderboard_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

class AbundanceDashboardSection extends StatefulWidget {
  const AbundanceDashboardSection({
    super.key,
    required this.theme,
    required this.goalsService,
  });

  final CompanyThemeData theme;
  final GoalsService goalsService;

  @override
  State<AbundanceDashboardSection> createState() =>
      _AbundanceDashboardSectionState();
}

class _AbundanceDashboardSectionState extends State<AbundanceDashboardSection> {
  late Future<_AbundanceDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  @override
  void didUpdateWidget(covariant AbundanceDashboardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme ||
        oldWidget.goalsService != widget.goalsService) {
      _dashboardFuture = _loadDashboard();
    }
  }

  Future<_AbundanceDashboardData> _loadDashboard() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return _AbundanceDashboardData.denied(theme: widget.theme);
    }
    final userId = session.id.toString();

    final userData = await UserService.getUserData();
    final companyName = _stringValue(userData['companyName']).isNotEmpty
        ? _stringValue(userData['companyName'])
        : widget.theme.companyName;
    final companyCode = _stringValue(userData['companyCode']).isNotEmpty
        ? _stringValue(userData['companyCode']).toUpperCase()
        : widget.theme.companyCode;
    final allowed = _isAbundanceCompany(name: companyName, code: companyCode);

    if (!allowed) {
      return _AbundanceDashboardData.denied(theme: widget.theme);
    }

    final goals = await widget.goalsService.watchGoals(userId).first;
    final joinedAt = _dateFrom(userData['createdAt']) ??
        _dateFrom(userData['joinedAt']) ??
        DateTime.now().subtract(const Duration(days: 365));

    final currentMonth = DateFormat('yyyy-MM').format(DateTime.now());
    final previousMonth = DateFormat('yyyy-MM')
        .format(DateTime(DateTime.now().year, DateTime.now().month - 1, 1));
    final dailyLogs = await _loadDailyLogs([currentMonth, previousMonth]);
    final emotionLogs = await _loadEmotionLogs([currentMonth, previousMonth]);
    final scoreInputs = UserScoreInputs(
      userId: userId,
      joinedAt: joinedAt,
      goals: goals
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
          .toList(),
      completionDays: _completionDaysFrom(dailyLogs),
      checkInDays: emotionLogs.map((log) => log.dayKey).toList(),
      activeCoreTaskCount: _abundanceTaskFields.length,
    );
    final score = computeUserScore(scoreInputs);
    final categoryStats = _buildCategoryStats(goals, score);
    final upcomingDeadlines = goals
        .where((goal) => goal.status != GoalStatus.completed)
        .where((goal) => goal.status != GoalStatus.abandoned)
        .toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
    final coach = await _loadCoachProfile();
    final councilRank = await _loadCouncilRank(
      userData: userData,
      currentUserId: userId,
      currentScore: score.coreTaskScore,
    );

    return _AbundanceDashboardData(
      allowed: true,
      theme: widget.theme,
      companyName: companyName,
      companyCode: companyCode,
      displayName: _displayNameFrom(userData, fallback: session.email),
      profilePic: _stringValue(userData['profilePic']),
      score: score,
      goalsCompleted:
          goals.where((goal) => goal.status == GoalStatus.completed).length,
      totalGoals: goals.length,
      currentStreak: score.currentStreak,
      checkInRate: score.checkInRate,
      categoryStats: categoryStats,
      upcomingDeadlines: upcomingDeadlines,
      momentumPoints: _buildMomentumPoints(
        dailyLogs: dailyLogs,
        emotionLogs: emotionLogs,
      ),
      coach: coach,
      councilRankLabel: councilRank.label,
      achievements: _buildAchievements(score, goals),
    );
  }

  // Coach assignment lives in the coach_mentees relationship table, not on
  // the user's own profile — see CoachApiService.fetchMyCoaches(). This
  // section only ever displays one coach, so the first assigned coach (if
  // any) is used.
  Future<_AbundanceCoachProfile?> _loadCoachProfile() async {
    final coaches = await CoachApiService.instance.fetchMyCoaches();
    if (coaches.isEmpty) return null;
    final coach = coaches.first;

    return _AbundanceCoachProfile(
      name: _displayNameFrom(
        {
          'fullName': coach['name'],
          'username': coach['name'],
          'email': coach['email'],
        },
        fallback: 'Coach',
      ),
      headline: 'Your support coach',
      profilePic: _stringValue(coach['profilePic']),
    );
  }

  Future<_AbundanceCouncilRank> _loadCouncilRank({
    required Map<String, dynamic> userData,
    required String currentUserId,
    required double currentScore,
  }) async {
    final snapshot = await LeaderboardApiService.instance.fetchLeaderboard();
    final entries = snapshot.entries;
    if (entries.isEmpty) {
      return const _AbundanceCouncilRank(rank: 1, total: 1);
    }

    final companyScoreMap = <String, double>{};
    for (final entry in entries) {
      companyScoreMap[entry.userId] = entry.score.toDouble();
    }
    companyScoreMap.putIfAbsent(currentUserId, () => currentScore);

    final current = companyScoreMap[currentUserId] ?? currentScore;
    final betterCount = companyScoreMap.values.where((value) => value > current).length;
    return _AbundanceCouncilRank(
      rank: betterCount + 1,
      total: companyScoreMap.length,
    );
  }

  Future<List<_AbundanceDailyLog>> _loadDailyLogs(List<String> months) async {
    final byDay = <String, _AbundanceDailyLog>{};
    for (final month in months) {
      try {
        final trackers = await DailyTrackerApiService.instance.fetchHistory(
          month: month,
        );
        for (final data in trackers) {
          final day = _dayKeyFrom(data);
          final timestamp = _dateFrom(data['updatedAt']) ??
              _dateFrom(data['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final completed = _countCheckedTasks(data);
          final log = _AbundanceDailyLog(
            dayKey: day,
            completedTasks: completed,
            totalTasks: _abundanceTaskFields.length,
            updatedAt: timestamp,
          );

          final existing = byDay[day];
          if (existing == null || log.updatedAt.isAfter(existing.updatedAt)) {
            byDay[day] = log;
          }
        }
      } catch (error) {
        debugPrint('Failed to load abundance daily logs: $error');
      }
    }

    final logs = byDay.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return logs;
  }

  Future<List<_AbundanceEmotionLog>> _loadEmotionLogs(List<String> months) async {
    final emotionByDay = <String, _AbundanceEmotionLog>{};
    for (final month in months) {
      try {
        final emotions = await EmotionService().fetchHistory(month: month);
        for (final data in emotions) {
          final day = _stringValue(data['date']).trim().isNotEmpty
              ? _stringValue(data['date']).trim()
              : DateFormat('yyyy-MM-dd').format(
                  _dateFrom(data['lastLoggedAt']) ??
                      _dateFrom(data['updatedAt']) ??
                      _dateFrom(data['createdAt']) ??
                      DateTime.now(),
                );
          final timestamp = _dateFrom(data['lastLoggedAt']) ??
              _dateFrom(data['updatedAt']) ??
              _dateFrom(data['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final emotion = _stringValue(data['emotion']).toLowerCase();
          if (emotion.isEmpty) continue;

          final log = _AbundanceEmotionLog(
            dayKey: day,
            emotion: emotion,
            loggedAt: timestamp,
          );

          final existing = emotionByDay[day];
          if (existing == null || log.loggedAt.isAfter(existing.loggedAt)) {
            emotionByDay[day] = log;
          }
        }
      } catch (error) {
        debugPrint('Failed to load abundance emotion logs: $error');
      }
    }

    final logs = emotionByDay.values.toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return logs;
  }

  Map<GoalCategory, _AbundanceCategoryStat> _buildCategoryStats(
    List<GoalSummary> goals,
    UserScore score,
  ) {
    final stats = <GoalCategory, _AbundanceCategoryStat>{
      for (final category in GoalCategory.values)
        category: const _AbundanceCategoryStat(
          totalGoals: 0,
          completedGoals: 0,
          score: 0,
        ),
    };

    for (final goal in goals) {
      final current = stats[goal.category]!;
      stats[goal.category] = _AbundanceCategoryStat(
        totalGoals: current.totalGoals + 1,
        completedGoals: current.completedGoals +
            (goal.status == GoalStatus.completed ? 1 : 0),
        score: score.categories[goal.category] ?? 0,
      );
    }

    return stats;
  }

  List<_AbundanceAchievement> _buildAchievements(
    UserScore score,
    List<GoalSummary> goals,
  ) {
    final completed =
        goals.where((goal) => goal.status == GoalStatus.completed).length;
    final hasAllCategories = requiredGoalGaps(goals).isEmpty;
    final hasAnyGoal = goals.isNotEmpty;
    final hasNoOverdue = goals.every((goal) => !goal.isOverdue);

    return [
      _AbundanceAchievement(
        title: 'First goal',
        subtitle: 'A goal is on the board.',
        icon: Icons.flag_rounded,
        unlocked: hasAnyGoal,
      ),
      _AbundanceAchievement(
        title: 'Balanced',
        subtitle: 'All three life areas are covered.',
        icon: Icons.balance_rounded,
        unlocked: hasAllCategories,
      ),
      _AbundanceAchievement(
        title: 'Momentum',
        subtitle: 'Current streak of 3 days.',
        icon: Icons.local_fire_department_rounded,
        unlocked: score.currentStreak >= 3,
      ),
      _AbundanceAchievement(
        title: 'Consistency',
        subtitle: 'Current streak of 7 days.',
        icon: Icons.trending_up_rounded,
        unlocked: score.currentStreak >= 7,
      ),
      _AbundanceAchievement(
        title: 'Finisher',
        subtitle: '$completed completed goals.',
        icon: Icons.verified_rounded,
        unlocked: completed >= 3,
      ),
      _AbundanceAchievement(
        title: 'Clear runway',
        subtitle: 'No overdue goals left behind.',
        icon: Icons.check_circle_rounded,
        unlocked: hasNoOverdue,
      ),
    ];
  }

  List<_AbundanceMomentumPoint> _buildMomentumPoints({
    required List<_AbundanceDailyLog> dailyLogs,
    required List<_AbundanceEmotionLog> emotionLogs,
  }) {
    final days = _lastNDays(7);
    final trackerByDay = <String, _AbundanceDailyLog>{
      for (final log in dailyLogs) log.dayKey: log,
    };
    final checkInsByDay = <String, _AbundanceEmotionLog>{
      for (final log in emotionLogs) log.dayKey: log,
    };

    return [
      for (final day in days)
        _AbundanceMomentumPoint(
          label: DateFormat('E').format(day),
          value: _dailyMomentumScore(
            trackerByDay[DateFormat('yyyy-MM-dd').format(day)],
            checkInsByDay[DateFormat('yyyy-MM-dd').format(day)],
          ),
        ),
    ];
  }

  double _dailyMomentumScore(
    _AbundanceDailyLog? log,
    _AbundanceEmotionLog? emotion,
  ) {
    final taskScore = log == null || log.totalTasks == 0
        ? 0.0
        : (log.completedTasks / log.totalTasks) * 100;
    final checkInBonus = emotion == null ? 0.0 : 100.0;
    return (taskScore * 0.7) + (checkInBonus * 0.3);
  }

  int _countCheckedTasks(Map<String, dynamic> data) {
    var completed = 0;
    for (final field in _abundanceTaskFields) {
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
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  String _stringValue(dynamic value) => value is String ? value.trim() : '';

  DateTime? _dateFrom(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  List<String> _completionDaysFrom(List<_AbundanceDailyLog> logs) {
    final days = <String>[];
    for (final log in logs) {
      for (var i = 0; i < log.completedTasks; i += 1) {
        days.add(log.dayKey);
      }
    }
    return days;
  }

  String _displayNameFrom(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final firstName = _stringValue(data['firstName']);
    final lastName = _stringValue(data['lastName']);
    final fullName = _stringValue(data['fullName']);
    final username = _stringValue(data['username']);
    final email = _stringValue(data['email']);

    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
    }
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    if (email.isNotEmpty) return email.split('@').first;
    return fallback;
  }

  bool _isAbundanceCompany({
    String name = '',
    String code = '',
  }) {
    return AbundanceCompany.matches(code, name);
  }

  List<DateTime> _lastNDays(int count) {
    final now = DateTime.now();
    return List<DateTime>.generate(
      count,
      (index) => DateTime(now.year, now.month, now.day).subtract(
        Duration(days: count - 1 - index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AbundanceDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _AbundanceLoadingCard(theme: widget.theme);
        }

        final data = snapshot.data!;
        if (!data.allowed) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final metrics = [
                  _AbundanceMiniMetricCard(
                    theme: widget.theme,
                    icon: CupertinoIcons.flame_fill,
                    title: 'Current streak',
                    value:
                        '${data.currentStreak} day${data.currentStreak == 1 ? '' : 's'}',
                  ),
                  _AbundanceMiniMetricCard(
                    theme: widget.theme,
                    icon: Icons.emoji_events_rounded,
                    title: 'Council rank',
                    value: data.councilRankLabel,
                  ),
                  _AbundanceMiniMetricCard(
                    theme: widget.theme,
                    icon: Icons.task_alt_rounded,
                    title: 'Goals completed',
                    value:
                        '${data.goalsCompleted} of ${data.totalGoals == 0 ? 3 : data.totalGoals}',
                  ),
                ];

                return _AbundanceScorePanel(
                  theme: widget.theme,
                  displayName: data.displayName,
                  companyName: data.companyName,
                  companyCode: data.companyCode,
                  profilePic: data.profilePic,
                  score: data.goalTotalScore,
                  scoreColor: _scoreColor(data.goalTotalScore, widget.theme),
                  currentStreak: data.currentStreak,
                  rankLabel: data.councilRankLabel,
                  goalsCompleted: data.goalsCompleted,
                  goalsTotal: data.totalGoals == 0 ? 3 : data.totalGoals,
                  checkInRate: data.checkInRate,
                  metricCards: metrics,
                  compactMetrics: constraints.maxWidth < 940,
                );
              },
            ),
            const SizedBox(height: 18),
            _AbundanceMomentumCard(
              theme: widget.theme,
              points: data.momentumPoints,
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final deadlines = _AbundanceDeadlinesCard(
                  theme: widget.theme,
                  goals: data.upcomingDeadlines,
                  onTap: (goal) => Navigator.of(context).pushNamed('/goalsHub'),
                );
                final coach = _AbundanceCoachCard(
                  theme: widget.theme,
                  coach: data.coach,
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: deadlines),
                      const SizedBox(width: 12),
                      Expanded(child: coach),
                    ],
                  );
                }

                return Column(
                  children: [
                    deadlines,
                    const SizedBox(height: 12),
                    coach,
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'Goals by category',
              subtitle: 'Your personal, professional and contribution focus.',
              actionLabel: 'All goals',
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final columns = constraints.maxWidth >= 960
                    ? 3
                    : constraints.maxWidth >= 620
                        ? 2
                        : 1;
                final cards = [
                  for (final category in GoalCategory.values)
                    _AbundanceCategoryCard(
                      theme: widget.theme,
                      category: category,
                      totalGoals:
                          data.categoryStats[category]?.totalGoals ?? 0,
                      completedGoals:
                          data.categoryStats[category]?.completedGoals ?? 0,
                      score: data.categoryStats[category]?.score ?? 0,
                      compact: compact,
                    ),
                ];

                if (compact) {
                  return SizedBox(
                    height: 170,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: cards.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 260,
                          child: cards[index],
                        );
                      },
                    ),
                  );
                }

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: columns == 2 ? 168 : 164,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) => cards[index],
                );
              },
            ),
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'Achievements',
              subtitle: 'Keep moving and these milestones light up.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  return _AbundanceAchievementCard(
                    theme: widget.theme,
                    achievement: data.achievements[index],
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: data.achievements.length,
              ),
            ),
          ],
        );
      },
    );
  }

}

class _AbundanceDashboardData {
  const _AbundanceDashboardData({
    required this.allowed,
    required this.theme,
    required this.companyName,
    required this.companyCode,
    required this.displayName,
    required this.profilePic,
    required this.score,
    required this.goalsCompleted,
    required this.totalGoals,
    required this.currentStreak,
    required this.checkInRate,
    required this.categoryStats,
    required this.upcomingDeadlines,
    required this.momentumPoints,
    required this.coach,
    required this.councilRankLabel,
    required this.achievements,
  });

  _AbundanceDashboardData.denied({required this.theme})
      : allowed = false,
        companyName = '',
        companyCode = '',
        displayName = '',
        profilePic = '',
        score = UserScore.empty(''),
        goalsCompleted = 0,
        totalGoals = 0,
        currentStreak = 0,
        checkInRate = 0,
        categoryStats = const <GoalCategory, _AbundanceCategoryStat>{},
        upcomingDeadlines = const <GoalSummary>[],
        momentumPoints = const <_AbundanceMomentumPoint>[],
        coach = null,
        councilRankLabel = '',
        achievements = const <_AbundanceAchievement>[];

  final bool allowed;
  final CompanyThemeData theme;
  final String companyName;
  final String companyCode;
  final String displayName;
  final String profilePic;
  final UserScore score;
  final int goalsCompleted;
  final int totalGoals;
  final int currentStreak;
  final double checkInRate;
  final Map<GoalCategory, _AbundanceCategoryStat> categoryStats;
  final List<GoalSummary> upcomingDeadlines;
  final List<_AbundanceMomentumPoint> momentumPoints;
  final _AbundanceCoachProfile? coach;
  final String councilRankLabel;
  final List<_AbundanceAchievement> achievements;

  // Named goalTotalScore for historical reasons (this dashboard used to
  // headline a pure goal-completion score); the ring now shows
  // coreTaskScore -- daily tracker completion only, matching the
  // leaderboard's daily-tracker-only ranking. Goal completion is still
  // tracked and shown separately via categoryStats/goalsCompleted below.
  double get goalTotalScore => score.coreTaskScore;
}

class _AbundanceCoachProfile {
  const _AbundanceCoachProfile({
    required this.name,
    required this.headline,
    required this.profilePic,
  });

  final String name;
  final String headline;
  final String profilePic;
}

class _AbundanceCouncilRank {
  const _AbundanceCouncilRank({
    required this.rank,
    required this.total,
  });

  final int rank;
  final int total;

  String get label => '$rank${_ordinalSuffix(rank)} of $total';
}

class _AbundanceDailyLog {
  const _AbundanceDailyLog({
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

class _AbundanceEmotionLog {
  const _AbundanceEmotionLog({
    required this.dayKey,
    required this.emotion,
    required this.loggedAt,
  });

  final String dayKey;
  final String emotion;
  final DateTime loggedAt;
}

class _AbundanceCategoryStat {
  const _AbundanceCategoryStat({
    required this.totalGoals,
    required this.completedGoals,
    required this.score,
  });

  final int totalGoals;
  final int completedGoals;
  final double score;
}

class _AbundanceMomentumPoint {
  const _AbundanceMomentumPoint({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;
}

class _AbundanceAchievement {
  const _AbundanceAchievement({
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

class _AbundanceLoadingCard extends StatelessWidget {
  const _AbundanceLoadingCard({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      child: const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _AbundanceMiniMetricCard extends StatelessWidget {
  const _AbundanceMiniMetricCard({
    required this.theme,
    required this.icon,
    required this.title,
    required this.value,
  });

  final CompanyThemeData theme;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: theme.iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.mutedInkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _AbundanceScorePanel extends StatelessWidget {
  const _AbundanceScorePanel({
    required this.theme,
    required this.displayName,
    required this.companyName,
    required this.companyCode,
    required this.profilePic,
    required this.score,
    required this.scoreColor,
    required this.currentStreak,
    required this.rankLabel,
    required this.goalsCompleted,
    required this.goalsTotal,
    required this.checkInRate,
    required this.metricCards,
    required this.compactMetrics,
  });

  final CompanyThemeData theme;
  final String displayName;
  final String companyName;
  final String companyCode;
  final String profilePic;
  final double score;
  final Color scoreColor;
  final int currentStreak;
  final String rankLabel;
  final int goalsCompleted;
  final int goalsTotal;
  final double checkInRate;
  final List<Widget> metricCards;
  final bool compactMetrics;

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100).toDouble();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.surfaceColor,
            Color.alphaBlend(theme.primaryColor.withValues(alpha: 0.14), theme.backgroundColor),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.16)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AbundancePill(
                label: companyCode.isNotEmpty ? companyCode : companyName,
                background: theme.iconColor.withValues(alpha: 0.14),
                foreground: theme.inkColor,
              ),
              _AbundancePill(
                label: 'Check-ins ${checkInRate.toStringAsFixed(0)}%',
                background: theme.iconColor.withValues(alpha: 0.14),
                foreground: theme.inkColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your goals, streak and council progress are all gathered here.',
                      style: TextStyle(
                        color: theme.mutedInkColor,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  _AbundanceScoreRing(score: clamped, accent: scoreColor),
                  const SizedBox(height: 10),
                  Text(
                    'Daily tracker score',
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.iconColor.withValues(alpha: 0.12),
                    backgroundImage:
                        profilePic.isNotEmpty ? NetworkImage(profilePic) : null,
                    child: profilePic.isNotEmpty
                        ? null
                        : Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: theme.inkColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (compactMetrics) ...[
            for (var i = 0; i < metricCards.length; i += 1) ...[
              metricCards[i],
              if (i != metricCards.length - 1) const SizedBox(height: 12),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(child: metricCards[0]),
                const SizedBox(width: 12),
                Expanded(child: metricCards[1]),
              ],
            ),
            const SizedBox(height: 12),
            metricCards[2],
          ],
        ],
      ),
    );
  }
}

class _AbundanceScoreRing extends StatelessWidget {
  const _AbundanceScoreRing({
    required this.score,
    required this.accent,
  });

  final double score;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 11,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  score.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'of 100',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _AbundancePill extends StatelessWidget {
  const _AbundancePill({
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
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AbundanceMomentumCard extends StatelessWidget {
  const _AbundanceMomentumCard({
    required this.theme,
    required this.points,
  });

  final CompanyThemeData theme;
  final List<_AbundanceMomentumPoint> points;

  @override
  Widget build(BuildContext context) {
    final hasData = points.any((point) => point.value > 0);
    final maxY = math.max(
      100.0,
      points.fold<double>(0, (total, point) => math.max(total, point.value + 10)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal analytics',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your goal total score, core tasks and consistency across the last 7 days.',
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: theme.iconColor.withValues(alpha: 0.12)),
                color: theme.backgroundColor.withValues(alpha: 0.32),
              ),
              child: hasData
                  ? LineChart(
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
                                if (value % 25 != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    color: theme.mutedInkColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= points.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    points[index].label,
                                    style: TextStyle(
                                      color: theme.mutedInkColor,
                                      fontSize: 11,
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
                    )
                  : _AbundanceEmptyStateCard(theme: theme),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbundanceEmptyStateCard extends StatelessWidget {
  const _AbundanceEmptyStateCard({required this.theme});

  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.graph_square,
              color: theme.iconColor,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No history yet',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scores are snapped daily. Come back tomorrow to see the line.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _AbundanceDeadlinesCard extends StatelessWidget {
  const _AbundanceDeadlinesCard({
    required this.theme,
    required this.goals,
    required this.onTap,
  });

  final CompanyThemeData theme;
  final List<GoalSummary> goals;
  final void Function(GoalSummary goal) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming deadlines',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Goals with target dates ahead of you.',
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (goals.isEmpty)
            Text(
              'Nothing due right now. You have room to keep building.',
              style: TextStyle(
                color: theme.mutedInkColor,
                height: 1.35,
              ),
            )
          else
            Column(
              children: [
                for (final goal in goals.take(2)) ...[
                  _AbundanceDeadlineTile(
                    goal: goal,
                    theme: theme,
                    onTap: () => onTap(goal),
                  ),
                  if (goal != goals.take(2).last)
                    Divider(color: theme.mutedInkColor.withValues(alpha: 0.12)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AbundanceDeadlineTile extends StatelessWidget {
  const _AbundanceDeadlineTile({
    required this.goal,
    required this.theme,
    required this.onTap,
  });

  final GoalSummary goal;
  final CompanyThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = GoalCategory.fromCode(goal.category.code);
    final color = Color(category.accent);
    final late = goal.isOverdue;
    final dueText = goal.isOverdue
        ? 'Overdue by ${goal.daysUntilDue.abs()} days'
        : goal.daysUntilDue == 0
            ? 'Due today'
            : '${goal.daysUntilDue} days left';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                late ? Icons.warning_amber_rounded : Icons.calendar_month_rounded,
                color: late ? Colors.red : color,
                size: 20,
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
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${category.label} · ${DateFormat.MMMd().format(goal.targetDate)}',
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: late
                    ? Colors.red.withValues(alpha: 0.08)
                    : theme.iconColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                dueText,
                style: TextStyle(
                  color: late ? Colors.red.shade700 : theme.iconColor,
                  fontSize: 10,
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

class _AbundanceCoachCard extends StatelessWidget {
  const _AbundanceCoachCard({
    required this.theme,
    required this.coach,
  });

  final CompanyThemeData theme;
  final _AbundanceCoachProfile? coach;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.iconColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach feedback',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The latest notes on your goals and check-ins.',
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (coach != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.backgroundColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
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
                          style: TextStyle(
                            color: theme.inkColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          coach!.headline,
                          style: TextStyle(
                            color: theme.mutedInkColor,
                            fontSize: 11,
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
          ],
          Container(
            height: 176,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.backgroundColor.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.iconColor.withValues(alpha: 0.12)),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.chat_bubble_2_fill,
                      color: theme.iconColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No feedback yet',
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your coach\'s comments on goals and check-ins will land here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.mutedInkColor,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AbundanceCategoryCard extends StatelessWidget {
  const _AbundanceCategoryCard({
    required this.theme,
    required this.category,
    required this.totalGoals,
    required this.completedGoals,
    required this.score,
    this.compact = false,
  });

  final CompanyThemeData theme;
  final GoalCategory category;
  final int totalGoals;
  final int completedGoals;
  final double score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.accent);
    final empty = totalGoals == 0;
    final completedLabel =
        empty ? '0 of 0 completed' : '$completedGoals of $totalGoals completed';

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: compact ? 18 : 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.14)),
                ),
                child: Text(
                  empty ? 'No goals' : '$totalGoals goal${totalGoals == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            score.toStringAsFixed(0),
            style: TextStyle(
              color: theme.iconColor,
              fontSize: compact ? 28 : 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            children: [
              Text(
                'Category score',
                style: TextStyle(
                  color: theme.mutedInkColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${(score).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: compact ? 8 : 12,
              value: (score / 100).clamp(0, 1),
              backgroundColor: theme.backgroundColor.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          SizedBox(height: compact ? 8 : 14),
          Text(
            completedLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.mutedInkColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AbundanceAchievementCard extends StatelessWidget {
  const _AbundanceAchievementCard({
    required this.theme,
    required this.achievement,
  });

  final CompanyThemeData theme;
  final _AbundanceAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final color = achievement.unlocked ? theme.iconColor : theme.mutedInkColor;
    return Container(
      width: 164,
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(24),
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
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.subtitle,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.mutedInkColor,
              height: 1.35,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.12)),
            ),
            child: Text(
              achievement.unlocked ? 'Unlocked' : 'Locked',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

String _ordinalSuffix(int value) {
  final mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return 'th';
  switch (value % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

const List<String> _abundanceTaskFields = <String>[
  'call',
  'steps',
  'exercise',
  'meditation',
  'learning',
  'addValue',
];
