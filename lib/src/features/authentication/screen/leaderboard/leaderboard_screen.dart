import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/app_route_observer.dart';
import 'package:selfcare_projects/src/services/leaderboard_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class UserActivity {
  const UserActivity({
    this.callIntent = 0,
    this.meditationMinutes = 0,
    this.stepsTaken = 0,
    this.exerciseCount = 0,
    this.valueEntries = 0,
    this.learningEntries = 0,
    this.todoListCount = 0,
  });

  final int callIntent;
  final int meditationMinutes;
  final int stepsTaken;
  final int exerciseCount;
  final int valueEntries;
  final int learningEntries;
  final int todoListCount;

  int calculatePoints() {
    return callIntent +
        meditationMinutes +
        (stepsTaken / 200).floor() +
        (exerciseCount * 10) +
        valueEntries +
        learningEntries +
        todoListCount;
  }
}

String _formatLeaderboardScore(num score) {
  // Normalize floating-point noise first so scores stay compact in the UI.
  final roundedToTenth = (score * 10).roundToDouble() / 10;
  return roundedToTenth == roundedToTenth.roundToDouble()
      ? roundedToTenth.toStringAsFixed(0)
      : roundedToTenth.toStringAsFixed(1);
}

String _formatLeaderboardDate(DateTime date) {
  return DateFormat('MMM d, yyyy').format(date.toLocal());
}

bool _isBeforeDate(DateTime left, DateTime right) {
  final normalizedLeft = DateTime(left.year, left.month, left.day);
  final normalizedRight = DateTime(right.year, right.month, right.day);
  return normalizedLeft.isBefore(normalizedRight);
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.name,
    required this.score,
    required this.rank,
    required this.activity,
    this.goalScore = 0,
    this.coreTaskScore = 0,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final num score;
  final int rank;
  final UserActivity activity;
  final num goalScore;
  final num coreTaskScore;
  final String? profilePic;
  final String? teamName;

  LeaderboardEntry copyWith({
    String? userId,
    String? name,
    num? score,
    int? rank,
    UserActivity? activity,
    num? goalScore,
    num? coreTaskScore,
    String? profilePic,
    String? teamName,
  }) {
    return LeaderboardEntry(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      activity: activity ?? this.activity,
      goalScore: goalScore ?? this.goalScore,
      coreTaskScore: coreTaskScore ?? this.coreTaskScore,
      profilePic: profilePic ?? this.profilePic,
      teamName: teamName ?? this.teamName,
    );
  }
}

class A12LeaderboardEntry {
  const A12LeaderboardEntry({
    required this.userId,
    required this.name,
    required this.score,
    required this.rank,
    required this.activity,
    this.profilePic,
    this.teamName,
  });

  final String userId;
  final String name;
  final UserScore score;
  final GoalRank rank;
  final UserActivity activity;
  final String? profilePic;
  final String? teamName;

  A12LeaderboardEntry copyWith({
    String? userId,
    String? name,
    UserScore? score,
    GoalRank? rank,
    UserActivity? activity,
    String? profilePic,
    String? teamName,
  }) {
    return A12LeaderboardEntry(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      activity: activity ?? this.activity,
      profilePic: profilePic ?? this.profilePic,
      teamName: teamName ?? this.teamName,
    );
  }
}

class GroupLeaderboardSummary {
  const GroupLeaderboardSummary({
    required this.groupId,
    required this.groupName,
    required this.coachName,
    required this.companyName,
    required this.totalScore,
    required this.entries,
    required this.photoUrl,
  });

  final String groupId;
  final String groupName;
  final String coachName;
  final String companyName;
  final num totalScore;
  final List<LeaderboardEntry> entries;
  final String? photoUrl;
}

class Leaderboard extends StatefulWidget {
  const Leaderboard({
    super.key,
    this.isLoading = true,
    this.debugLoader,
  });

  final bool isLoading;
  final Future<LeaderboardApiSnapshot> Function()? debugLoader;

  @override
  State<Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<Leaderboard>
    with WidgetsBindingObserver, RouteAware {
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();
  Timer? _refreshTimer;

  List<LeaderboardEntry> _allEntries = [];
  List<A12LeaderboardEntry> _a12Entries = [];
  List<LeaderboardEntry> _menteeEntries = [];
  List<GroupLeaderboardSummary> _groupLeaderboards = [];
  bool _isLoading = true;
  bool _isA12Loading = true;
  bool _isRefreshing = false;
  bool _isAbundanceCompany = false;
  bool _isCoachUser = false;
  String? _loadError;
  String? _loadErrorDetails;
  DateTime? _leaderboardPeriodStart;
  DateTime? _leaderboardPeriodEnd;
  ModalRoute<dynamic>? _route;

  bool _isAbundanceCompanyByIdentity({
    String name = '',
    String code = '',
  }) {
    return AbundanceCompany.matches(code, name);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      unawaited(_refreshLeaderboard(silent: true));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  Future<void> _bootstrap() async {
    await _loadLeaderboardFromApi();
  }

  A12LeaderboardEntry _toA12Entry(LeaderboardApiCompanyEntry entry) {
    final score = entry.overallScore.toDouble();
    final goalScore = entry.goalScore.toDouble();
    final dailyTrackerScore = entry.coreTaskScore.toDouble();
    return A12LeaderboardEntry(
      userId: entry.userId,
      name: entry.name,
      score: UserScore(
        userId: entry.userId,
        categories: {for (final c in GoalCategory.values) c: 0.0},
        goalScore: goalScore,
        coreTaskScore: dailyTrackerScore,
        consistencyScore: 0,
        overallScore: score,
        currentStreak: 0,
        longestStreak: 0,
        goalsTotal: 0,
        goalsCompleted: 0,
        taskCompletionRate: 0,
        checkInRate: 0,
      ),
      rank: rankForPercent(score),
      activity: const UserActivity(),
      profilePic: entry.profilePic,
      teamName: entry.teamName,
    );
  }

  Future<void> _loadLeaderboardFromApi() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _allEntries = const <LeaderboardEntry>[];
        _a12Entries = const <A12LeaderboardEntry>[];
        _menteeEntries = const <LeaderboardEntry>[];
        _groupLeaderboards = const <GroupLeaderboardSummary>[];
        _isLoading = false;
        _isA12Loading = false;
        _isAbundanceCompany = false;
        _isCoachUser = false;
        _loadError = 'Your session has expired. Please sign in again.';
        _loadErrorDetails = 'No active app session was available.';
        _leaderboardPeriodStart = null;
        _leaderboardPeriodEnd = null;
      });
      return;
    }

    try {
      final loader = widget.debugLoader;
      final snapshot = loader != null
          ? await loader()
          : await LeaderboardApiService.instance.fetchLeaderboard();
      final companyEntries = snapshot.entries;
      final rankedAll = companyEntries
          .map(
            (entry) => LeaderboardEntry(
              userId: entry.userId,
              name: entry.name,
              score: entry.overallScore,
              rank: entry.rank,
              activity: const UserActivity(),
              goalScore: entry.goalScore,
              coreTaskScore: entry.coreTaskScore,
              profilePic: entry.profilePic,
              teamName: entry.teamName,
            ),
          )
          .toList()
        ..sort((a, b) {
          if (a.score != b.score) {
            return b.score.compareTo(a.score);
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      final rankedCompany = rankedAll.asMap().entries.map((entry) {
        return entry.value.copyWith(rank: entry.key + 1);
      }).toList();
      final a12Entries = companyEntries.map(_toA12Entry).toList();
      final groups = snapshot.groups
          .map(
            (group) => GroupLeaderboardSummary(
              groupId: group.groupId,
              groupName: group.groupName,
              coachName: group.coachName,
              companyName: group.companyName,
              totalScore: group.totalScore,
              photoUrl: group.photoUrl,
              entries: group.entries
                  .map(
                    (member) => LeaderboardEntry(
                      userId: member.userId,
                      name: member.name,
                      score: member.overallScore,
                      rank: member.rank,
                      activity: const UserActivity(),
                      goalScore: member.goalScore,
                      coreTaskScore: member.coreTaskScore,
                      profilePic: member.profilePic,
                      teamName: member.teamName,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();
      final menteeEntries = snapshot.menteeEntries
          .map(
            (member) => LeaderboardEntry(
              userId: member.userId,
              name: member.name,
              score: member.overallScore,
              rank: member.rank,
              activity: const UserActivity(),
              goalScore: member.goalScore,
              coreTaskScore: member.coreTaskScore,
              profilePic: member.profilePic,
              teamName: member.teamName,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _isAbundanceCompany = _isAbundanceCompanyByIdentity(
          name: snapshot.companyName,
          code: snapshot.companyCode,
        );
        _isCoachUser = session.isCoach;
        _leaderboardPeriodStart = snapshot.leaderboardPeriodStart;
        _leaderboardPeriodEnd = snapshot.leaderboardPeriodEnd;
        _a12Entries = a12Entries;
        _allEntries = rankedCompany;
        _menteeEntries = menteeEntries.isEmpty ? rankedCompany : menteeEntries;
        _groupLeaderboards = groups;
        _loadError = null;
        _loadErrorDetails = null;
        _isLoading = false;
        _isA12Loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Leaderboard API load failed: $error');
      debugPrintStack(
        label: 'Leaderboard API stack trace',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadError = switch (error) {
          ApiException(statusCode: 401) =>
            'Your session has expired. Please sign in again.',
          ApiException(statusCode: >= 500) =>
            'The server could not load the leaderboard.',
          ApiException() => error.message,
          _ => 'Unable to load the leaderboard right now.',
        };
        _loadErrorDetails = error.toString();
        _isLoading = false;
        _isA12Loading = false;
      });
    }
  }

  // [silent] skips the loading-skeleton flags for refreshes the user
  // didn't ask for (the periodic timer, returning to this screen,
  // resuming the app) -- toggling them back to true swaps the real
  // content out for a skeleton and back again, which resets whatever the
  // user was scrolled to. A user-initiated refresh (the refresh button,
  // pull-to-refresh) still shows the loading state, since that's expected
  // feedback for a deliberate action.
  Future<void> _refreshLeaderboard({bool silent = false}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _isA12Loading = true;
      });
    }
    try {
      await _loadLeaderboardFromApi();
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void didPopNext() {
    unawaited(_refreshLeaderboard(silent: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLeaderboard(silent: true));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return DefaultTabController(
          length: 2,
          child: Theme(
            data: Theme.of(context).copyWith(
              scaffoldBackgroundColor: companyTheme.backgroundColor,
              cardColor: companyTheme.surfaceColor,
              textTheme: Theme.of(context).textTheme.apply(
                    bodyColor: companyTheme.inkColor,
                    displayColor: companyTheme.inkColor,
                  ),
              tabBarTheme: TabBarThemeData(
                labelColor: companyTheme.isDark
                    ? companyTheme.primaryColor
                    : companyTheme.inkColor,
                unselectedLabelColor: companyTheme.mutedInkColor,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            child: Scaffold(
              backgroundColor: companyTheme.backgroundColor,
              appBar: AppBar(
                elevation: 0,
                backgroundColor:
                    companyTheme.isDark ? companyTheme.surfaceColor : null,
                foregroundColor:
                    companyTheme.isDark ? companyTheme.inkColor : null,
                surfaceTintColor: Colors.transparent,
                title: const Text('Leaderboard'),
                actions: [
                  IconButton(
                    key: const ValueKey('leaderboard-info-button'),
                    icon: const Icon(Icons.help_outline_rounded),
                    tooltip: 'How scoring works',
                    onPressed: () => _showLeaderboardInfo(context, companyTheme),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshLeaderboard,
                  ),
                  IconButton(
                    icon:
                        const Icon(CupertinoIcons.line_horizontal_3, size: 28),
                    onPressed: () {
                      Navigator.pushNamed(context, '/profile');
                    },
                  ),
                ],
                bottom: TabBar(
                  isScrollable: true,
                  indicatorColor: companyTheme.primaryColor,
                  tabs: [
                    const Tab(text: 'Company'),
                    const Tab(text: 'Groups'),
                  ],
                ),
              ),
              body: Column(
                children: [
                  if (_leaderboardPeriodStart != null &&
                      _leaderboardPeriodEnd != null)
                    _LeaderboardPeriodBanner(
                      start: _leaderboardPeriodStart!,
                      end: _leaderboardPeriodEnd!,
                      userCount: _a12Entries.length,
                      theme: companyTheme,
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      key: _refreshKey,
                      onRefresh: _refreshLeaderboard,
                      child: _loadError != null && _a12Entries.isEmpty
                          ? _LeaderboardLoadError(
                              message: _loadError!,
                              details: _loadErrorDetails,
                              theme: companyTheme,
                              onRetry: _refreshLeaderboard,
                            )
                          : TabBarView(
                              children: [
                                _A12LeaderboardBoard(
                                  key: const ValueKey('company'),
                                  entries: _a12Entries,
                                  isLoading: _isA12Loading,
                                  theme: companyTheme,
                                  currentUserId: AuthService
                                          .instance.currentSession?.id
                                          .toString() ??
                                      '',
                                  showRankLabels: _isAbundanceCompany,
                                  title: 'Company leaderboard',
                                  onEntryTap: (entry) => _showScoreBreakdown(
                                    context,
                                    entry,
                                    companyTheme,
                                  ),
                                ),
                                _GroupLeaderboardsBoard(
                                  groups: _groupLeaderboards,
                                  allMenteeEntries: _isCoachUser
                                      ? _menteeEntries
                                      : _allEntries,
                                  isLoading: _isLoading,
                                  isCoachUser: _isCoachUser,
                                  view: _CoachLeaderboardView.groups,
                                  theme: companyTheme,
                                  onEntryTap: (entry) => _showPointsBreakdown(
                                    context,
                                    entry,
                                    companyTheme,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLeaderboardInfo(BuildContext context, CompanyThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 12,
              ),
              child: LeaderboardInfoSheet(theme: theme),
            );
          },
        );
      },
    );
  }

  void _showPointsBreakdown(
    BuildContext context,
    LeaderboardEntry entry,
    CompanyThemeData theme,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: GroupLeaderboardScoreBreakdownSheet(
              entry: entry,
              theme: theme,
            ),
          ),
        );
      },
    );
  }

  void _showScoreBreakdown(
    BuildContext context,
    A12LeaderboardEntry entry,
    CompanyThemeData theme,
  ) {
    final accentColor =
        _isAbundanceCompany ? _rankColor(entry.rank) : theme.primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: LeaderboardScoreBreakdownSheet(
              name: entry.name,
              teamName: entry.teamName,
              goalScore: entry.score.goalScore,
              dailyTrackerScore: entry.score.coreTaskScore,
              totalScore: entry.score.overallScore,
              accentColor: accentColor,
              theme: theme,
            ),
          ),
        );
      },
    );
  }
}

class _LeaderboardLoadError extends StatelessWidget {
  const _LeaderboardLoadError({
    required this.message,
    required this.details,
    required this.theme,
    required this.onRetry,
  });

  final String message;
  final String? details;
  final CompanyThemeData theme;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        color: theme.primaryColor,
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.inkColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (details?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(
                          details!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.mutedInkColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class LeaderboardInfoSheet extends StatelessWidget {
  const LeaderboardInfoSheet({super.key, required this.theme});

  final CompanyThemeData theme;

  static const _sections = [
    _LeaderboardInfoSection(
      icon: Icons.checklist_rounded,
      title: 'Daily Tracker score',
      body:
          'Every day you have a set of core activities -- things like Call, '
          'Steps, Exercise, Meditation, Learning, and Add Value. Each one is '
          'worth an equal share of the day. There\'s no partial credit for '
          'an activity -- it\'s either done or it isn\'t.',
      example: 'Completed 4 of 6 activities\n'
          '4 ÷ 6 × 100 = 66.7% for that day',
    ),
    _LeaderboardInfoSection(
      icon: Icons.leaderboard_rounded,
      title: 'Leaderboard ranking',
      body:
          'Your Overall Score -- the number that determines your rank -- '
          'comes entirely from how consistently you complete your Daily '
          'Tracker. Everyone in your company is ranked by this Overall '
          'Score, highest first. If your company runs a set leaderboard '
          'period, only what happens inside that date range counts.',
      example: 'Completed 4 of 6 Daily Tracker activities\n'
          '4 ÷ 6 × 100 = 66.7% Overall Score',
    ),
    _LeaderboardInfoSection(
      icon: Icons.workspace_premium_rounded,
      title: 'Medals & streaks',
      body:
          'Medals are earned by building daily streaks on Meditation, '
          'Steps, Exercise, and Fasting -- each has its own streak. '
          'Completing an activity today or yesterday keeps its streak '
          'alive; going a full day without it resets that streak back to '
          'zero. Once a medal is unlocked, it\'s yours to keep even if the '
          'streak later resets.',
      example: 'Streak milestones (days): 3, 7, 14, 30, 60, 100\n'
          'A 14-day streak unlocks the 3, 7, and 14-day medals at once',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.mutedInkColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Text(
          'How scoring works',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.inkColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A quick guide to how your Daily Tracker, Goals, medals, and '
          'Leaderboard rank are calculated.',
          style: TextStyle(fontSize: 14, color: theme.mutedInkColor, height: 1.35),
        ),
        const SizedBox(height: 18),
        for (final section in _sections) ...[
          _LeaderboardInfoCard(section: section, theme: theme),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardInfoSection {
  const _LeaderboardInfoSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.example,
  });

  final IconData icon;
  final String title;
  final String body;
  final String example;
}

class _LeaderboardInfoCard extends StatelessWidget {
  const _LeaderboardInfoCard({required this.section, required this.theme});

  final _LeaderboardInfoSection section;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: theme.isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: theme.isDark ? 0.22 : 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(section.icon, color: theme.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.inkColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.body,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: theme.mutedInkColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.surfaceColor.withValues(
                      alpha: theme.isDark ? 0.55 : 0.85,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.primaryColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXAMPLE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: theme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        section.example,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: theme.inkColor,
                          height: 1.4,
                        ),
                      ),
                    ],
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

class GroupLeaderboardScoreBreakdownSheet extends StatelessWidget {
  const GroupLeaderboardScoreBreakdownSheet({
    super.key,
    required this.entry,
    required this.theme,
  });

  final LeaderboardEntry entry;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LeaderboardScoreBreakdownSheet(
      name: entry.name,
      teamName: entry.teamName,
      goalScore: entry.goalScore,
      dailyTrackerScore: entry.coreTaskScore,
      totalScore: entry.score,
      accentColor: theme.primaryColor,
      theme: theme,
    );
  }
}

class LeaderboardScoreBreakdownSheet extends StatelessWidget {
  const LeaderboardScoreBreakdownSheet({
    super.key,
    required this.name,
    required this.goalScore,
    required this.dailyTrackerScore,
    required this.totalScore,
    required this.accentColor,
    required this.theme,
    this.teamName,
  });

  final String name;
  final String? teamName;
  final num goalScore;
  final num dailyTrackerScore;
  final num totalScore;
  final Color accentColor;
  final CompanyThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$name score',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.inkColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Leaderboard rank is based on the Daily tracker score only.',
          style: TextStyle(
            fontSize: 14,
            color: theme.mutedInkColor,
          ),
        ),
        if ((teamName ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Team: $teamName',
            style: TextStyle(
              fontSize: 14,
              color: theme.mutedInkColor,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildScoreBreakdownRow(
          'Daily tracker',
          dailyTrackerScore,
          'Today\'s tracker completion',
          dailyTrackerScore,
          theme,
        ),
        Divider(color: theme.mutedInkColor.withValues(alpha: 0.18)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall score (ranking)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.inkColor,
                ),
              ),
              Text(
                _formatLeaderboardScore(totalScore),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _buildScoreBreakdownRow(
  String title,
  num value,
  String rate,
  num points,
  CompanyThemeData theme,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            style: TextStyle(fontSize: 16, color: theme.inkColor),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            _formatLeaderboardScore(value),
            style: TextStyle(fontSize: 16, color: theme.inkColor),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            rate,
            style: TextStyle(fontSize: 14, color: theme.mutedInkColor),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${_formatLeaderboardScore(points)} pts',
            style: TextStyle(
              fontSize: 16,
              color: theme.isDark ? theme.primaryColor : Colors.orange,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class _LeaderboardPeriodBanner extends StatelessWidget {
  const _LeaderboardPeriodBanner({
    required this.start,
    required this.end,
    required this.userCount,
    required this.theme,
  });

  final DateTime start;
  final DateTime end;
  final int userCount;
  final CompanyThemeData theme;

  Widget _buildPill({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: theme.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.mutedInkColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUpcoming = _isBeforeDate(DateTime.now(), start);
    final subtitle = isUpcoming
        ? 'Scores stay at 0% until the start date.'
        : 'Scores count only inside this date window.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              theme.primaryColor.withValues(alpha: theme.isDark ? 0.2 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              CupertinoIcons.calendar,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leaderboard period',
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.mutedInkColor,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPill(
                      label: 'Total users',
                      value: userCount.toString(),
                    ),
                    _buildPill(
                      label: 'Starts',
                      value: _formatLeaderboardDate(start),
                    ),
                    _buildPill(
                      label: 'Ends',
                      value: _formatLeaderboardDate(end),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _rankColor(GoalRank rank) {
  switch (rank.key) {
    case 'TITAN':
      return const Color(0xFFE0A94F);
    case 'MASTER_IMMORTAL':
      return const Color(0xFFB56AE5);
    case 'IMMORTAL':
      return const Color(0xFF58A6FF);
    case 'DIVINE':
      return const Color(0xFF4DD4C6);
    case 'ANCIENT':
      return const Color(0xFF65B86B);
    case 'LEGEND':
      return const Color(0xFFEA8C55);
    case 'ARCHON':
      return const Color(0xFFE46D6D);
    case 'CRUSADER':
      return const Color(0xFF76A9FA);
    case 'GUARDIAN':
      return const Color(0xFF8FBC8F);
    case 'HERALD':
    default:
      return const Color(0xFF8B927E);
  }
}

enum _CoachLeaderboardView { groups }

class _GroupLeaderboardsBoard extends StatefulWidget {
  const _GroupLeaderboardsBoard({
    required this.groups,
    required this.allMenteeEntries,
    required this.isLoading,
    required this.isCoachUser,
    required this.view,
    required this.theme,
    required this.onEntryTap,
  });

  final List<GroupLeaderboardSummary> groups;
  final List<LeaderboardEntry> allMenteeEntries;
  final bool isLoading;
  final bool isCoachUser;
  final _CoachLeaderboardView view;
  final CompanyThemeData theme;
  final ValueChanged<LeaderboardEntry> onEntryTap;

  @override
  State<_GroupLeaderboardsBoard> createState() =>
      _GroupLeaderboardsBoardState();
}

class _GroupLeaderboardsBoardState extends State<_GroupLeaderboardsBoard> {
  String? _selectedGroupId;

  @override
  void didUpdateWidget(covariant _GroupLeaderboardsBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedGroupId == null) return;
    final stillExists = widget.groups.any(
      (group) => group.groupId == _selectedGroupId,
    );
    if (!stillExists) {
      _selectedGroupId = null;
    }
  }

  GroupLeaderboardSummary? get _selectedGroup {
    if (_selectedGroupId == null) return null;
    for (final group in widget.groups) {
      if (group.groupId == _selectedGroupId) return group;
    }
    return null;
  }

  List<LeaderboardEntry> get _selectedEntries {
    final group = _selectedGroup;
    return group == null ? widget.allMenteeEntries : group.entries;
  }

  num get _selectedTotalScore {
    final group = _selectedGroup;
    if (group != null) return group.totalScore;
    return widget.allMenteeEntries.fold<num>(
      0,
      (runningTotal, entry) => runningTotal + entry.score,
    );
  }

  String _formatScore(num score) {
    return _formatLeaderboardScore(score);
  }

  String get _selectedTitle => _selectedGroup?.groupName ?? 'All mentees';

  Widget _buildSelectionChips() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All mentees'),
              selected: _selectedGroupId == null,
              onSelected: (_) => setState(() => _selectedGroupId = null),
            ),
          ),
          ...widget.groups.map((group) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: group.photoUrl != null
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(
                          ImageStorageService.normalizeMediaUrl(
                            group.photoUrl,
                          ),
                        ),
                      )
                    : null,
                label: Text(group.groupName),
                selected: _selectedGroupId == group.groupId,
                onSelected: (_) {
                  setState(() => _selectedGroupId = group.groupId);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSelectedSummaryCard() {
    final group = _selectedGroup;
    final theme = widget.theme;
    final subtitle = group == null
        ? 'Leaderboard of every accepted mentee under this coach.'
        : group.companyName.isNotEmpty
            ? 'Coach ${group.coachName} • ${group.entries.length} mentees in this group • ${group.companyName}.'
            : 'Coach ${group.coachName} • ${group.entries.length} mentees in this group.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: theme.isDark
            ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
            : null,
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: theme.isDark ? 0.12 : 0.12),
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.isDark
                  ? theme.primaryColor.withValues(alpha: 0.16)
                  : const Color(0xFFF4E6C8),
              borderRadius: BorderRadius.circular(16),
              image: group?.photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(
                        ImageStorageService.normalizeMediaUrl(
                          group!.photoUrl,
                        ),
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: group?.photoUrl != null
                ? null
                : Icon(
                    group == null
                        ? CupertinoIcons.person_2_fill
                        : CupertinoIcons.rectangle_grid_2x2_fill,
                    color: theme.isDark
                        ? theme.primaryColor
                        : const Color(0xFF6F7B5C),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: theme.inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.mutedInkColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_formatScore(_selectedTotalScore)} pts',
            style: TextStyle(
              color: theme.isDark ? theme.primaryColor : Colors.orange,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupPodiumItem({
    required GroupLeaderboardSummary group,
    required int rank,
    required double height,
    required Color color,
  }) {
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: rank == 1 ? 27 : 23,
                backgroundColor: color.withValues(alpha: 0.18),
                backgroundImage: group.photoUrl != null
                    ? NetworkImage(
                        ImageStorageService.normalizeMediaUrl(
                          group.photoUrl,
                        ),
                      )
                    : null,
                child: group.photoUrl == null
                    ? Text(
                        '#$rank',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : null,
              ),
              if (group.photoUrl != null)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 84,
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.85),
                  color,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  group.groupName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_formatScore(group.totalScore)} pts',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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

  Widget _buildGroupPodium(List<GroupLeaderboardSummary> groups) {
    final theme = widget.theme;
    if (groups.length < 3) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: theme.isDark
              ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
              : null,
          boxShadow: [
            BoxShadow(
              color: (theme.isDark ? theme.primaryColor : Colors.black)
                  .withValues(alpha: 0.12),
              blurRadius: 4,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          'Create at least 3 groups to show a group podium.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.mutedInkColor),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: theme.isDark
            ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
            : null,
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.12),
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top 3 groups',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: theme.inkColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildGroupPodiumItem(
                group: groups[1],
                rank: 2,
                height: 108,
                color: const Color(0xFF8B927E),
              ),
              _buildGroupPodiumItem(
                group: groups[0],
                rank: 1,
                height: 134,
                color: const Color(0xFFE0A94F),
              ),
              _buildGroupPodiumItem(
                group: groups[2],
                rank: 3,
                height: 92,
                color: const Color(0xFF9B7B60),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupLeaderboardItem({
    required BuildContext context,
    required GroupLeaderboardSummary group,
    required int rank,
  }) {
    final theme = widget.theme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: theme.isDark
            ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
            : null,
        boxShadow: [
          BoxShadow(
            color: (theme.isDark ? theme.primaryColor : Colors.black)
                .withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>(group.groupId),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          collapsedIconColor: theme.mutedInkColor,
          iconColor: theme.primaryColor,
          maintainState: true,
          leading: CircleAvatar(
            backgroundColor: theme.primaryColor.withValues(alpha: 0.14),
            backgroundImage: group.photoUrl != null
                ? NetworkImage(
                    ImageStorageService.normalizeMediaUrl(group.photoUrl),
                  )
                : null,
            child: group.photoUrl == null
                ? Icon(
                    CupertinoIcons.rectangle_grid_2x2_fill,
                    size: 18,
                    color: theme.primaryColor,
                  )
                : null,
          ),
          title: Text(
            group.groupName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: theme.inkColor,
            ),
          ),
          subtitle: Text(
            group.companyName.isNotEmpty
                ? 'Coach ${group.coachName} · ${group.entries.length} mentees · ${group.companyName}'
                : 'Coach ${group.coachName} · ${group.entries.length} mentees',
            style: TextStyle(color: theme.mutedInkColor),
          ),
          trailing: Text(
            '${_formatScore(group.totalScore)} pts',
            style: TextStyle(
              color: theme.isDark ? theme.primaryColor : Colors.orange,
              fontWeight: FontWeight.w900,
            ),
          ),
          children: [
            if (group.entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No mentees yet.',
                  style: TextStyle(color: theme.mutedInkColor),
                ),
              )
            else
              ...group.entries.asMap().entries.map(
                (memberEntry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildGroupMemberRow(
                      memberEntry.value,
                      position: memberEntry.key + 1,
                      theme: theme,
                    ),
                  );
                },
              ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Group total score',
                    style: TextStyle(
                      color: theme.inkColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${_formatScore(group.totalScore)} pts',
                    style: TextStyle(
                      color: theme.isDark ? theme.primaryColor : Colors.orange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupMemberRow(
    LeaderboardEntry entry, {
    required int position,
    required CompanyThemeData theme,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onEntryTap(entry),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(
            alpha: theme.isDark ? 0.22 : 0.5,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.mutedInkColor.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.primaryColor.withValues(alpha: 0.16),
              backgroundImage:
                  entry.profilePic != null && entry.profilePic!.isNotEmpty
                      ? NetworkImage(entry.profilePic!)
                      : null,
              child: entry.profilePic == null || entry.profilePic!.isEmpty
                  ? Text(
                      entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: theme.primaryColor,
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
                    '#$position ${entry.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.inkColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((entry.teamName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.teamName!,
                      style: TextStyle(
                        color: theme.mutedInkColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_formatScore(entry.score)} pts',
              style: TextStyle(
                color: theme.isDark ? theme.primaryColor : Colors.orange,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenteeLeaderboardTab(BuildContext context) {
    final entries = _selectedEntries;
    final listEntries =
        entries.length >= 3 ? entries.skip(3).toList() : entries;

    return Column(
      children: [
        const SizedBox(height: 14),
        _buildSelectionChips(),
        _buildSelectedSummaryCard(),
        SizedBox(
          height: 220,
          child: _buildPodium(
            context,
            entries,
            _selectedGroup == null
                ? 'No mentee scores yet.'
                : 'No scores in this group yet.',
            widget.onEntryTap,
            widget.theme,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _selectedGroup == null
                          ? 'No mentee scores yet.'
                          : 'No mentees in this group yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: listEntries.length,
                  itemBuilder: (context, index) {
                    return _buildLeaderboardItem(
                      listEntries[index],
                      widget.onEntryTap,
                      widget.theme,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGroupLeaderboardTab() {
    final groups = widget.groups.toList()
      ..sort((a, b) {
        if (a.totalScore != b.totalScore) {
          return b.totalScore.compareTo(a.totalScore);
        }
        return a.groupName.toLowerCase().compareTo(
              b.groupName.toLowerCase(),
            );
      });

    if (groups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No coach groups yet. Create groups from the coach dashboard.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildGroupPodium(groups),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Group leaderboard',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ...groups.asMap().entries.map((entry) {
          return _buildGroupLeaderboardItem(
            context: context,
            group: entry.value,
            rank: entry.key + 1,
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return _LeaderboardBoard(
        entries: const [],
        isLoading: true,
        emptyMessage: '',
        theme: widget.theme,
        onEntryTap: widget.onEntryTap,
      );
    }

    if (widget.groups.isEmpty && widget.allMenteeEntries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No accepted mentees yet. Once mentees connect, their leaderboard will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    if (widget.view == _CoachLeaderboardView.groups) {
      return _buildGroupLeaderboardTab();
    }

    return _buildMenteeLeaderboardTab(context);
  }
}

class _LeaderboardBoard extends StatelessWidget {
  const _LeaderboardBoard({
    super.key,
    required this.entries,
    required this.isLoading,
    required this.emptyMessage,
    required this.theme,
    required this.onEntryTap,
  });

  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final String emptyMessage;
  final CompanyThemeData theme;
  final ValueChanged<LeaderboardEntry> onEntryTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: isLoading
              ? _buildSkeletonPodium()
              : _buildPodium(
                  context,
                  entries,
                  emptyMessage,
                  onEntryTap,
                  theme,
                ),
        ),
        Expanded(
          child: isLoading
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _buildSkeletonItem(),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length <= 3 ? 0 : entries.length - 3,
                  itemBuilder: (context, index) {
                    final entry = entries[index + 3];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _buildLeaderboardItem(entry, onEntryTap, theme),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSkeletonPodium() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildSkeletonPodiumItem(120),
        _buildSkeletonPodiumItem(140),
        _buildSkeletonPodiumItem(100),
      ],
    );
  }

  Widget _buildSkeletonPodiumItem(double height) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const ShimmerWidget.circular(size: 48),
        const SizedBox(height: 8),
        const ShimmerWidget.rectangular(width: 30, height: 16),
        Container(
          width: 80,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: ShimmerWidget.rectangular(width: 80, height: height),
        ),
      ],
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFE5D3),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const ShimmerWidget.rectangular(width: 30, height: 24),
          const SizedBox(width: 12),
          const ShimmerWidget.circular(size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerWidget.rectangular(width: double.infinity, height: 16),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerWidget.rectangular(width: double.infinity, height: 2),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              ShimmerWidget.rectangular(width: 40, height: 24),
              SizedBox(height: 4),
              ShimmerWidget.rectangular(width: 20, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllUsersLeaderboardBoard extends StatefulWidget {
  const _AllUsersLeaderboardBoard({
    required this.legacyEntries,
    required this.a12Entries,
    required this.isLoading,
    required this.isA12Loading,
    required this.showRankLabels,
    required this.theme,
    required this.currentUserId,
    required this.onLegacyEntryTap,
    required this.onA12EntryTap,
  });

  final List<LeaderboardEntry> legacyEntries;
  final List<A12LeaderboardEntry> a12Entries;
  final bool isLoading;
  final bool isA12Loading;
  final bool showRankLabels;
  final CompanyThemeData theme;
  final String currentUserId;
  final ValueChanged<LeaderboardEntry> onLegacyEntryTap;
  final ValueChanged<A12LeaderboardEntry> onA12EntryTap;

  @override
  State<_AllUsersLeaderboardBoard> createState() =>
      _AllUsersLeaderboardBoardState();
}

class _AllUsersLeaderboardBoardState extends State<_AllUsersLeaderboardBoard> {
  bool _showA12 = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Legacy points'),
                selected: !_showA12,
                onSelected: (_) => setState(() => _showA12 = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Company score'),
                selected: _showA12,
                onSelected: (_) => setState(() => _showA12 = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.02, 0.04),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: _showA12
                ? _A12LeaderboardBoard(
                    key: const ValueKey('a12'),
                    entries: widget.a12Entries,
                    isLoading: widget.isA12Loading,
                    theme: theme,
                    currentUserId: widget.currentUserId,
                    showRankLabels: widget.showRankLabels,
                    onEntryTap: widget.onA12EntryTap,
                  )
                : _LeaderboardBoard(
                    key: const ValueKey('legacy'),
                    entries: widget.legacyEntries,
                    isLoading: widget.isLoading,
                    emptyMessage: 'No leaderboard entries to display.',
                    theme: theme,
                    onEntryTap: widget.onLegacyEntryTap,
                  ),
          ),
        ),
      ],
    );
  }
}

class _A12LeaderboardBoard extends StatefulWidget {
  const _A12LeaderboardBoard({
    super.key,
    required this.entries,
    required this.isLoading,
    required this.theme,
    required this.currentUserId,
    required this.showRankLabels,
    this.title = 'Company leaderboard',
    required this.onEntryTap,
  });

  final List<A12LeaderboardEntry> entries;
  final bool isLoading;
  final CompanyThemeData theme;
  final String currentUserId;
  final bool showRankLabels;
  final String title;
  final ValueChanged<A12LeaderboardEntry> onEntryTap;

  @override
  State<_A12LeaderboardBoard> createState() => _A12LeaderboardBoardState();
}

class _A12LeaderboardBoardState extends State<_A12LeaderboardBoard> {
  static const _summaryCardKey = ValueKey<String>('current-user-score-card');
  static const _scrollDuration = Duration(milliseconds: 520);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _leaderboardIntroKey = GlobalKey();
  final GlobalKey _firstRankedRowKey = GlobalKey();
  final GlobalKey _currentUserRowKey = GlobalKey();

  List<A12LeaderboardEntry> get entries => widget.entries;
  bool get isLoading => widget.isLoading;
  CompanyThemeData get theme => widget.theme;
  String get currentUserId => widget.currentUserId;
  bool get showRankLabels => widget.showRankLabels;
  String get title => widget.title;
  ValueChanged<A12LeaderboardEntry> get onEntryTap => widget.onEntryTap;

  List<A12LeaderboardEntry> get _sortedEntries {
    final sorted = [...entries];
    sorted.sort((a, b) {
      if (a.score.overallScore != b.score.overallScore) {
        return b.score.overallScore.compareTo(a.score.overallScore);
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToCurrentUser() async {
    if (!_scrollController.hasClients || currentUserId.isEmpty) return;

    final sorted = _sortedEntries;
    final placement = sorted.indexWhere(
      (entry) => entry.userId == currentUserId,
    );
    if (placement < 0) return;

    // The first three users are represented by the podium rather than list
    // rows, so their destination is the top of the leaderboard.
    if (placement < 3) {
      await _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: _scrollDuration,
        curve: Curves.easeInOutCubic,
      );
      return;
    }

    final mountedRow = _currentUserRowKey.currentContext;
    if (mountedRow != null) {
      await Scrollable.ensureVisible(
        mountedRow,
        duration: _scrollDuration,
        curve: Curves.easeInOutCubic,
        alignment: 0.12,
      );
      return;
    }

    final introRenderObject =
        _leaderboardIntroKey.currentContext?.findRenderObject();
    final introHeight =
        introRenderObject is RenderBox && introRenderObject.hasSize
            ? introRenderObject.size.height
            : 0.0;
    final firstRowRenderObject =
        _firstRankedRowKey.currentContext?.findRenderObject();
    final precedingRowExtent =
        firstRowRenderObject is RenderBox && firstRowRenderObject.hasSize
            ? firstRowRenderObject.size.height
            : showRankLabels
                ? 112.0
                : 86.0;
    final rowIndex = placement - 3;
    final rawOffset = introHeight + (rowIndex * precedingRowExtent);
    final position = _scrollController.position;
    final targetOffset = rawOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    // Seek by rank first so Flutter mounts a distant lazy list row, then use
    // its real layout position for the final, exact alignment.
    await _scrollController.animateTo(
      targetOffset,
      duration: _scrollDuration,
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final rowContext = _currentUserRowKey.currentContext;
    if (rowContext != null && rowContext.mounted) {
      await Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    }
  }

  LeaderboardEntry _toLegacyEntry(A12LeaderboardEntry entry) {
    return LeaderboardEntry(
      userId: entry.userId,
      name: entry.name,
      score: entry.score.overallScore,
      rank: 0,
      activity: entry.activity,
      goalScore: entry.score.goalScore,
      coreTaskScore: entry.score.coreTaskScore,
      profilePic: entry.profilePic,
      teamName: entry.teamName,
    );
  }

  Widget _buildCompanyPodium(
    BuildContext context,
    List<A12LeaderboardEntry> sortedEntries,
  ) {
    if (sortedEntries.length < 3) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: theme.isDark
              ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
              : null,
          boxShadow: [
            BoxShadow(
              color: (theme.isDark ? theme.primaryColor : Colors.black)
                  .withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          'Create at least 3 company scores to show a podium.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.mutedInkColor),
        ),
      );
    }

    final podiumEntries = sortedEntries.take(3).toList();
    final podiumLegacy = podiumEntries.map(_toLegacyEntry).toList();

    return SizedBox(
      height: 220,
      child: _buildPodium(
        context,
        podiumLegacy,
        'No company scores yet.',
        (entry) {
          final original = sortedEntries.firstWhere(
            (candidate) => candidate.userId == entry.userId,
            orElse: () => sortedEntries.first,
          );
          onEntryTap(original);
        },
        theme,
      ),
    );
  }

  A12LeaderboardEntry? get _currentUserEntry {
    for (final entry in entries) {
      if (entry.userId == currentUserId) return entry;
    }
    return null;
  }

  Widget _buildHeaderCard(A12LeaderboardEntry? entry) {
    final score = entry?.score.overallScore ?? 0;
    final rank = entry?.rank ?? rankForPercent(0);
    final scoreColor = showRankLabels ? _rankColor(rank) : theme.primaryColor;

    if (!showRankLabels) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.primaryColor
                .withValues(alpha: theme.isDark ? 0.22 : 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scoreColor.withValues(alpha: 0.88),
                    scoreColor.withValues(alpha: 0.58),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatLeaderboardScore(score),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'Score',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry?.name.isNotEmpty == true ? entry!.name : 'You',
                    style: TextStyle(
                      color: theme.inkColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Based on your Daily tracker completion.',
                    style: TextStyle(
                      color: theme.mutedInkColor,
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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scoreColor.withValues(alpha: theme.isDark ? 0.26 : 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: scoreColor.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scoreColor.withValues(alpha: 0.88),
                  scoreColor.withValues(alpha: 0.58),
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatLeaderboardScore(score),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Score',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry?.name.isNotEmpty == true ? entry!.name : 'You',
                  style: TextStyle(
                    color: theme.inkColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Based on your Daily tracker completion.',
                  style: TextStyle(
                    color: theme.mutedInkColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.88, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    key: ValueKey(rank.key),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: scoreColor.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      'Level ${rank.name}',
                      style: TextStyle(
                        color: scoreColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildA12MetricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: theme.isDark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: theme.mutedInkColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(A12LeaderboardEntry entry, int position) {
    final isCurrentUser = entry.userId == currentUserId;
    final rankColor =
        showRankLabels ? _rankColor(entry.rank) : theme.primaryColor;
    final progress = (entry.score.overallScore / 100).clamp(0.0, 1.0);
    final scoreLabel = _formatLeaderboardScore(entry.score.overallScore);

    final item = GestureDetector(
      key: ValueKey<String>('leaderboard-entry-${entry.userId}'),
      onTap: () => onEntryTap(entry),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCurrentUser
                ? rankColor.withValues(alpha: 0.45)
                : theme.primaryColor.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: (isCurrentUser ? rankColor : Colors.black)
                  .withValues(alpha: theme.isDark ? 0.12 : 0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: rankColor.withValues(alpha: 0.18),
              backgroundImage:
                  entry.profilePic != null && entry.profilePic!.isNotEmpty
                      ? NetworkImage(entry.profilePic!)
                      : null,
              child: entry.profilePic == null || entry.profilePic!.isEmpty
                  ? Text(
                      entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: rankColor,
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
                  Row(
                    children: [
                      Text(
                        '#$position',
                        style: TextStyle(
                          color: theme.inkColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.inkColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (showRankLabels)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale:
                                    Tween<double>(begin: 0.92, end: 1).animate(
                                  animation,
                                ),
                                child: child,
                              ),
                            );
                          },
                          child: Container(
                            key: ValueKey(entry.rank.key),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: rankColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.rank.name,
                              style: TextStyle(
                                color: rankColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      if (isCurrentUser) ...[
                        if (showRankLabels) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor:
                          theme.mutedInkColor.withValues(alpha: 0.14),
                      valueColor: AlwaysStoppedAnimation<Color>(rankColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$scoreLabel%',
                  style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Score',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: theme.mutedInkColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return isCurrentUser
        ? KeyedSubtree(key: _currentUserRowKey, child: item)
        : item;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CircularProgressIndicator(
            color: theme.primaryColor,
          ),
        ),
      );
    }

    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No company scores yet. Finish goals and daily tracker tasks to build your level.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final sorted = _sortedEntries;
    final currentUserEntry = _currentUserEntry;
    // Keep the list populated for small company datasets so the company
    // leaderboard still shows the available users instead of a blank section.
    final remainingEntries =
        sorted.length >= 3 ? sorted.skip(3).toList() : sorted;
    final scoreColor = showRankLabels
        ? _rankColor(currentUserEntry?.rank ?? rankForPercent(0))
        : theme.primaryColor;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Column(
          key: _leaderboardIntroKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                'Company podium',
                style: TextStyle(
                  color: theme.inkColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _buildCompanyPodium(context, sorted),
            Semantics(
              button: currentUserEntry != null,
              label:
                  currentUserEntry == null ? null : 'Show my leaderboard rank',
              child: GestureDetector(
                key: _summaryCardKey,
                behavior: HitTestBehavior.opaque,
                onTap: currentUserEntry == null ? null : _scrollToCurrentUser,
                child: _buildHeaderCard(currentUserEntry),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  _buildA12MetricChip(
                    label: 'Goal score',
                    value:
                        '${_formatLeaderboardScore(currentUserEntry?.score.goalScore ?? 0)}%',
                    color: scoreColor,
                  ),
                  const SizedBox(width: 10),
                  _buildA12MetricChip(
                    label: 'Daily tracker',
                    value:
                        '${_formatLeaderboardScore(currentUserEntry?.score.coreTaskScore ?? 0)}%',
                    color: theme.primaryColor,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        ...remainingEntries.asMap().entries.map((entry) {
          final item = entry.value;
          final row = _buildItem(item, entry.key + 4);
          return entry.key == 0
              ? KeyedSubtree(key: _firstRankedRowKey, child: row)
              : row;
        }),
      ],
    );
  }
}

Widget _buildPodium(
  BuildContext context,
  List<LeaderboardEntry> entries,
  String emptyMessage,
  ValueChanged<LeaderboardEntry> onEntryTap,
  CompanyThemeData theme,
) {
  if (entries.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          emptyMessage,
          style: TextStyle(fontSize: 16, color: theme.mutedInkColor),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  if (entries.length < 3) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Not enough entries to display podium (need at least 3)',
          style: TextStyle(fontSize: 16, color: theme.mutedInkColor),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  return SingleChildScrollView(
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 0,
          top: 20,
          child: SizedBox(
            width: 100,
            height: 180,
            child: _TransparentConfettiBurst(
              mirror: false,
              primaryColor: theme.primaryColor,
              accentColor: theme.accentColor,
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 20,
          child: SizedBox(
            width: 100,
            height: 180,
            child: _TransparentConfettiBurst(
              mirror: true,
              primaryColor: theme.primaryColor,
              accentColor: theme.accentColor,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildPodiumItem(entries[1], 120, 2, onEntryTap, theme),
            _buildPodiumItem(entries[0], 140, 1, onEntryTap, theme),
            _buildPodiumItem(entries[2], 100, 3, onEntryTap, theme),
          ],
        ),
      ],
    ),
  );
}

Widget _buildPodiumItem(
  LeaderboardEntry entry,
  double height,
  int position,
  ValueChanged<LeaderboardEntry> onEntryTap,
  CompanyThemeData theme,
) {
  return GestureDetector(
    onTap: () => onEntryTap(entry),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          children: [
            entry.profilePic != null && entry.profilePic!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      entry.profilePic!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey[200],
                          child: Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  )
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.grey[200],
                    child: Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.grey[600],
                    ),
                  ),
            if (position == 1)
              Positioned(
                top: 13,
                child: Image.asset(
                  'assets/images/crown.png',
                  height: 50,
                  width: 100,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Stack(
            children: [
              Container(
                width: 80,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.isDark
                          ? theme.primaryColor
                          : const Color(0xFF59BDB3),
                      theme.isDark
                          ? theme.accentColor
                          : const Color(0xFF3E9189),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Center(
                  child: Text(
                    '${_formatLeaderboardScore(entry.score)} pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: height / 4,
                left: 0,
                right: 0,
                child: Text(
                  entry.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Text(
                  'Top $position',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildLeaderboardItem(
  LeaderboardEntry entry,
  ValueChanged<LeaderboardEntry> onEntryTap,
  CompanyThemeData theme,
) {
  final cardColor = theme.surfaceColor;
  final shadowColor = (theme.isDark ? theme.primaryColor : Colors.black)
      .withValues(alpha: theme.isDark ? 0.12 : 0.12);

  return GestureDetector(
    onTap: () => onEntryTap(entry),
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: theme.isDark
            ? Border.all(color: theme.primaryColor.withValues(alpha: 0.18))
            : null,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 4,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '#${entry.rank}',
            style: TextStyle(
              color: theme.inkColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[200],
            backgroundImage:
                entry.profilePic != null && entry.profilePic!.isNotEmpty
                    ? NetworkImage(entry.profilePic!)
                    : null,
            child: entry.profilePic == null || entry.profilePic!.isEmpty
                ? Icon(Icons.person, size: 30, color: Colors.grey[600])
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    color: theme.inkColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: entry.score > 0
                        ? (entry.score / 100).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 8,
                    backgroundColor:
                        theme.mutedInkColor.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.isDark ? theme.primaryColor : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatLeaderboardScore(entry.score),
                style: TextStyle(
                  color: theme.inkColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'pts',
                style: TextStyle(color: theme.mutedInkColor, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TransparentConfettiBurst extends StatelessWidget {
  const _TransparentConfettiBurst({
    required this.mirror,
    required this.primaryColor,
    required this.accentColor,
  });

  final bool mirror;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _TransparentConfettiPainter(
          mirror: mirror,
          primaryColor: primaryColor,
          accentColor: accentColor,
        ),
      ),
    );
  }
}

class _TransparentConfettiPainter extends CustomPainter {
  const _TransparentConfettiPainter({
    required this.mirror,
    required this.primaryColor,
    required this.accentColor,
  });

  final bool mirror;
  final Color primaryColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pieces = <_ConfettiPiece>[
      const _ConfettiPiece(0.18, 0.12, 8, 3, -0.6, 0),
      const _ConfettiPiece(0.44, 0.08, 5, 5, 0.2, 1),
      const _ConfettiPiece(0.72, 0.18, 10, 3, 0.7, 2),
      const _ConfettiPiece(0.26, 0.34, 7, 3, 0.5, 3),
      const _ConfettiPiece(0.58, 0.31, 4, 4, -0.2, 0),
      const _ConfettiPiece(0.84, 0.42, 9, 3, -0.8, 1),
      const _ConfettiPiece(0.16, 0.55, 5, 5, 0.3, 2),
      const _ConfettiPiece(0.48, 0.61, 11, 3, 0.9, 3),
      const _ConfettiPiece(0.72, 0.73, 6, 4, -0.4, 0),
      const _ConfettiPiece(0.34, 0.84, 8, 3, -0.7, 1),
    ];
    final colors = <Color>[
      primaryColor,
      accentColor,
      Colors.amber,
      const Color(0xFF76E4F7),
    ];

    for (final piece in pieces) {
      final dx = mirror ? 1 - piece.x : piece.x;
      final center = Offset(dx * size.width, piece.y * size.height);
      final paint = Paint()
        ..color = colors[piece.colorIndex % colors.length].withValues(
          alpha: 0.78,
        )
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(piece.rotation * math.pi);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: piece.width,
        height: piece.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TransparentConfettiPainter oldDelegate) {
    return oldDelegate.mirror != mirror ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _ConfettiPiece {
  const _ConfettiPiece(
    this.x,
    this.y,
    this.width,
    this.height,
    this.rotation,
    this.colorIndex,
  );

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int colorIndex;
}

class ShimmerWidget extends StatefulWidget {
  const ShimmerWidget.rectangular({
    super.key,
    required this.width,
    required this.height,
  }) : isCircular = false;

  const ShimmerWidget.circular({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        isCircular = true;

  final double width;
  final double height;
  final bool isCircular;

  @override
  State<ShimmerWidget> createState() => _ShimmerWidgetState();
}

class _ShimmerWidgetState extends State<ShimmerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(
              widget.isCircular ? widget.width / 2 : 4,
            ),
            gradient: LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(-_animation.value, 0),
              colors: [
                Colors.grey[300]!,
                Colors.grey[100]!,
                Colors.grey[300]!,
              ],
            ),
          ),
        );
      },
    );
  }
}
