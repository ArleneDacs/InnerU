import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_backdrop.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';

/// The Abundance 12 quests hub. This keeps the feature isolated to A12
/// company users while giving them the richer dashboard-style layout.
class GoalsHubScreen extends StatefulWidget {
  const GoalsHubScreen({
    super.key,
    this.service,
    this.uid,
    this.accessResolver,
  });

  final GoalsService? service;
  final String? uid;
  final Future<bool> Function(String uid)? accessResolver;

  @override
  State<GoalsHubScreen> createState() => _GoalsHubScreenState();
}

class _GoalsHubScreenState extends State<GoalsHubScreen> {
  late final GoalsService _service;
  late final String _uid;
  late final Future<bool> _hasAccessFuture;

  GoalCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalsService();
    _uid =
        widget.uid ?? AuthService.instance.currentSession?.id.toString() ?? '';
    _hasAccessFuture = _resolveAccess();
  }

  Future<bool> _resolveAccess() async {
    if (_uid.isEmpty) return false;
    final accessResolver = widget.accessResolver;
    if (accessResolver != null) {
      return accessResolver(_uid);
    }
    // Prefer resolving access from this screen's own GoalsService, which is
    // injectable/testable. This only returns non-null when a legacy
    // Firestore is configured (test mode); in production, GoalsService()
    // never carries one, so this is a no-op and behavior below is unchanged.
    final identity = await _service.fetchActiveCompanyIdentity(_uid);
    if (identity != null) {
      return AbundanceCompany.matches(identity.code, identity.name);
    }
    final membership = await CompanyMembershipService.loadForUser(_uid);
    return _isAbundanceCompany(membership.activeMembership);
  }

  bool _isAbundanceCompany(CompanyMembership? membership) {
    return AbundanceCompany.matches(membership?.code, membership?.name);
  }

  void _openForm({GoalSummary? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalFormScreen(
          service: _service,
          uid: _uid,
          existing: existing,
        ),
      ),
    );
  }

  void _openDetail(GoalSummary goal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(
          goalId: goal.id,
          service: _service,
          uid: _uid,
        ),
      ),
    );
  }

  List<ScorableGoal> _toScorableGoals(List<GoalSummary> goals) {
    return goals
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
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasAccessFuture,
      builder: (context, accessSnapshot) {
        if (accessSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (accessSnapshot.data != true) {
          return Scaffold(
            backgroundColor: _bg,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A12 only',
                          style: TextStyle(
                            color: _accentGold,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'The Quests experience is available for Abundance 12 company members only.',
                          style: TextStyle(
                            color: _muted,
                            height: 1.5,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accentGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                          child: const Text('Go back'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<GoalSummary>>(
          stream: _service.watchGoals(_uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final goals = snapshot.data ?? const <GoalSummary>[];
            final activeGoals = goals
                .where((goal) => goal.status != GoalStatus.abandoned)
                .toList();
            final categories = scoreCategories(_toScorableGoals(activeGoals));
            final overallScore = weightGoalScore(categories).round();
            final completedCount = activeGoals
                .where((goal) => goal.status == GoalStatus.completed)
                .length;
            final inProgressCount = activeGoals
                .where((goal) => openGoalStatuses.contains(goal.status))
                .length;
            final overdueCount =
                activeGoals.where((goal) => goal.isOverdue).length;
            final categoryCounts = {
              for (final category in GoalCategory.values)
                category: activeGoals
                    .where((goal) => goal.category == category)
                    .length,
            };

            final visibleGoals = _selectedCategory == null
                ? activeGoals
                : activeGoals
                    .where((goal) => goal.category == _selectedCategory)
                    .toList();

            return Scaffold(
              backgroundColor: _bg,
              // The Quests screens carry A12's ambient hero plate behind
              // them (design spec, "Image assets": scoped to these screens
              // rather than the shared shell chrome every company uses).
              body: AbundanceBackdrop(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1500),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GoalsHeader(
                              onNewGoal: _openForm,
                            ),
                            const SizedBox(height: 20),
                            _GoalsSummaryGrid(
                              goalScore: overallScore,
                              totalGoals: activeGoals.length,
                              completedGoals: completedCount,
                              inProgressGoals: inProgressCount,
                              overdueGoals: overdueCount,
                              categoryScores: categories,
                            ),
                            const SizedBox(height: 20),
                            _CategoryChipsRow(
                              selectedCategory: _selectedCategory,
                              counts: categoryCounts,
                              onSelect: (category) {
                                setState(() => _selectedCategory = category);
                              },
                            ),
                            const SizedBox(height: 20),
                            if (visibleGoals.isEmpty)
                              _EmptyGoalsState(
                                hasFilter: _selectedCategory != null,
                                onNewGoal: _openForm,
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 1280
                                      ? 3
                                      : constraints.maxWidth >= 860
                                          ? 2
                                          : 1;
                                  const gap = 18.0;
                                  final cardWidth = columns == 1
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth -
                                              (gap * (columns - 1))) /
                                          columns;

                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final goal in visibleGoals)
                                        SizedBox(
                                          width: cardWidth,
                                          child: _GoalCard(
                                            goal: goal,
                                            service: _service,
                                            onTap: () => _openDetail(goal),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GoalsHeader extends StatelessWidget {
  const _GoalsHeader({required this.onNewGoal});

  final VoidCallback onNewGoal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        final title = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quests',
              style: TextStyle(
                color: _text,
                fontSize: 28,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                fontFamily: 'Georgia',
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Personal, professional and contribution - combined into your Life Power.',
              style: TextStyle(
                color: _muted,
                fontSize: 15.5,
                height: 1.45,
              ),
            ),
          ],
        );

        final button = FilledButton.icon(
          onPressed: onNewGoal,
          icon: const Icon(Icons.add, size: 20),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'New quest',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _accentGold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 24),
            button,
          ],
        );
      },
    );
  }
}

class _GoalsSummaryGrid extends StatelessWidget {
  const _GoalsSummaryGrid({
    required this.goalScore,
    required this.totalGoals,
    required this.completedGoals,
    required this.inProgressGoals,
    required this.overdueGoals,
    required this.categoryScores,
  });

  final int goalScore;
  final int totalGoals;
  final int completedGoals;
  final int inProgressGoals;
  final int overdueGoals;
  final Map<GoalCategory, double> categoryScores;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1120;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 360,
                child: _ScorePanel(score: goalScore),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'TOTAL QUESTS',
                            value: '$totalGoals',
                            icon: Icons.adjust_rounded,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _MetricCard(
                            label: 'COMPLETED',
                            value: '$completedGoals',
                            icon: Icons.flag_outlined,
                            valueColor: AbundanceColors.scoreExcellent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'IN PROGRESS',
                            value: '$inProgressGoals',
                            icon: Icons.calendar_month_outlined,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _MetricCard(
                            label: 'OVERDUE',
                            value: '$overdueGoals',
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final tileWidth = (constraints.maxWidth - 12) / 2;

        return Column(
          children: [
            _ScorePanel(score: goalScore),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _MetricCard(
                    label: 'TOTAL QUESTS',
                    value: '$totalGoals',
                    icon: Icons.adjust_rounded,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricCard(
                    label: 'COMPLETED',
                    value: '$completedGoals',
                    icon: Icons.flag_outlined,
                    valueColor: AbundanceColors.scoreExcellent,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricCard(
                    label: 'IN PROGRESS',
                    value: '$inProgressGoals',
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricCard(
                    label: 'OVERDUE',
                    value: '$overdueGoals',
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    final ringSize = compact ? 176.0 : 220.0;
    final outerPadding = compact ? 18.0 : 24.0;
    return Container(
      padding: EdgeInsets.all(outerPadding),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  // A12 treats this ring as the headline "Life Power" arc — a
                  // gold accent rather than the score-critical palette, since
                  // a low aggregate score is expected, not an error state.
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: compact ? 10 : 12,
                    backgroundColor: _trackBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      _accentGold,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        color: _accentGold,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'of 100',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Life Power',
            style: TextStyle(
              color: _text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your Personal, Professional and Contribution scores, combined into one out of 100.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _trackBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              icon,
              color: _chipGray,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? _text,
                    fontSize: 22,
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

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.selectedCategory,
    required this.counts,
    required this.onSelect,
  });

  final GoalCategory? selectedCategory;
  final Map<GoalCategory, int> counts;
  final ValueChanged<GoalCategory?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            count: counts.values.fold<int>(0, (total, value) => total + value),
            selected: selectedCategory == null,
            onTap: () => onSelect(null),
          ),
          const SizedBox(width: 14),
          for (final category in GoalCategory.values) ...[
            _FilterChip(
              label: category.label,
              count: counts[category] ?? 0,
              selected: selectedCategory == category,
              onTap: () => onSelect(category),
            ),
            const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _accentGold.withValues(alpha: 0.16) : _panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _accentGold : _border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '$label  $count',
          style: TextStyle(
            color: selected ? _accentGold : _muted,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.service,
    required this.onTap,
  });

  final GoalSummary goal;
  final GoalsService service;
  final VoidCallback onTap;

  Color get _progressColor {
    if (goal.status == GoalStatus.completed)
      return AbundanceColors.scoreExcellent;
    if (goal.isOverdue) return AbundanceColors.scoreCritical;
    return AbundanceColors.primaryGold;
  }

  String _statusLabel(GoalStatus status) {
    return switch (status) {
      GoalStatus.notStarted => 'Not started',
      GoalStatus.inProgress => 'In progress',
      GoalStatus.atRisk => 'At risk',
      GoalStatus.completed => 'Completed',
      GoalStatus.abandoned => 'Abandoned',
    };
  }

  Color _statusForeground(GoalStatus status) {
    return switch (status) {
      GoalStatus.notStarted => _chipGray,
      GoalStatus.inProgress => _chipBlue,
      GoalStatus.atRisk => _chipPink,
      GoalStatus.completed => _chipGreen,
      GoalStatus.abandoned => AbundanceColors.scoreCritical,
    };
  }

  // A12's QuestCard: `${overdue} ${overdue === 1 ? "day" : "days"} overdue`,
  // "Due today", or `${daysLeft} ${daysLeft === 1 ? "day" : "days"} left`.
  String _daysLabel(int daysLeft) {
    if (daysLeft < 0) {
      final overdue = -daysLeft;
      return '$overdue ${overdue == 1 ? 'day' : 'days'} overdue';
    }
    if (daysLeft == 0) return 'Due today';
    return '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left';
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = AbundanceColors.categoryColor(goal.category.code);
    final scoreColor = AbundanceColors.scoreColorFor(goal.progress);

    return StreamBuilder<List<ActionPlanItem>>(
      stream: service.watchPlans(goal.id),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const <ActionPlanItem>[];
        final completedPlans =
            plans.where((plan) => plan.status == ActionPlanStatus.done).length;
        final missionsLabel =
            '$completedPlans / ${plans.length} ${plans.length == 1 ? 'Mission' : 'Missions'}';
        final overdue = goal.isOverdue;
        final dueLabel = _daysLabel(goal.daysUntilDue);

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            // The category's own scene sits behind the card content under a
            // bottom-up scrim, mirroring A12's `rpg/quest-card.tsx`, which
            // renders `<Scene imageUrl={SCENES.quest[category]} tone={category}
            // scrimVariant="card" />` in an absolutely-positioned layer
            // beneath the badge row and title.
            child: Stack(
              children: [
                Positioned.fill(
                  child: AbundanceQuestScene(categoryCode: goal.category.code),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Badge(
                            text: goal.category.label,
                            color: categoryColor,
                            background: categoryColor.withValues(alpha: 0.12),
                          ),
                          _Badge(
                            text: _statusLabel(goal.status),
                            color: _statusForeground(goal.status),
                            background: _statusForeground(goal.status)
                                .withValues(alpha: 0.12),
                          ),
                          _Badge(
                            text: 'Score ${goal.progress}',
                            color: scoreColor,
                            background: scoreColor.withValues(alpha: 0.12),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                abundanceRankMedalAsset(goal.rank.key),
                                width: 20,
                                height: 20,
                              ),
                              const SizedBox(width: 6),
                              _Badge(
                                text: goal.rank.name,
                                color: _chipGray,
                                background: _chipGrayBg,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        goal.title,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          fontFamily: 'Georgia',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((goal.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          goal.description!,
                          style: const TextStyle(
                            color: _muted,
                            height: 1.45,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        '${goal.progress}',
                        style: TextStyle(
                          color: _progressColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: (goal.progress / 100).clamp(0.0, 1.0),
                          backgroundColor: _trackBg,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_progressColor),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.checklist_rounded,
                                  color: _muted,
                                  size: 15,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    missionsLabel,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                color: overdue
                                    ? AbundanceColors.scoreCritical
                                    : _muted,
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                dueLabel,
                                style: TextStyle(
                                  color: overdue
                                      ? AbundanceColors.scoreCritical
                                      : _muted,
                                  fontSize: 12.5,
                                  fontWeight: overdue
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyGoalsState extends StatelessWidget {
  const _EmptyGoalsState({
    required this.hasFilter,
    required this.onNewGoal,
  });

  final bool hasFilter;
  final VoidCallback onNewGoal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.adjust_rounded,
            size: 40,
            color: _muted,
          ),
          const SizedBox(height: 10),
          Text(
            hasFilter ? 'No quests in this category yet' : 'No quests yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          // The header's version of this claim was already corrected; the
          // same off-source sentence survived here because the header's
          // regression test seeds a goal, so the empty state never renders.
          // It named a "Todo List" destination this shell does not have and
          // a start/end date pair the wizard never collects (it collects one
          // deadline). The filtered case is now A12's own copy verbatim
          // (goals/page.tsx:263); the unfiltered case has no A12 equivalent
          // -- A12 always renders this page under a category -- so it gets
          // neutral copy pointing at the button directly below it.
          Text(
            hasFilter
                ? 'All three categories are required — an empty one scores 0. '
                    'Set a quest here to lift your Quest Total Score.'
                : 'Tap New quest to set your first quest and start building '
                    'your Life Power.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onNewGoal,
            style: FilledButton.styleFrom(
              backgroundColor: _accentGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('New quest'),
          ),
        ],
      ),
    );
  }
}

// Sourced from AbundanceColors (lib/src/features/abundance/theme/abundance_theme.dart)
// rather than new magic hex, mirroring the same alias approach used in
// goal_detail_screen.dart so both Quests screens trace every solid color
// back to the single shared source of truth. The "*Bg" variants below are
// subtle tinted backgrounds with no AbundanceColors equivalent (chip/badge
// backgrounds only) and remain as bespoke hex, same as the detail screen.
const Color _bg = AbundanceColors.background;
const Color _panel = AbundanceColors.surfaceRaised;
const Color _border = AbundanceColors.border;
const Color _text = AbundanceColors.foreground;
const Color _muted = AbundanceColors.muted;
const Color _accentGold = AbundanceColors.primaryGold;
const Color _trackBg = AbundanceColors.surfaceSunken;
const Color _chipGray = AbundanceColors.muted;
const Color _chipGrayBg = Color(0xFF232A47);
const Color _chipBlue = AbundanceColors.accentCyan;
const Color _chipPink = AbundanceColors.scoreCritical;
const Color _chipGreen = AbundanceColors.scoreExcellent;
