import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';

/// The Abundance 12 goals hub. This keeps the feature isolated to A12
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
    final membership = await CompanyMembershipService.loadForUser(_uid);
    return _isAbundance12Company(membership.activeMembership);
  }

  bool _isAbundance12Company(CompanyMembership? membership) {
    final companyName = membership?.name ?? '';
    final companyCode = membership?.code ?? '';
    final normalizedName =
        companyName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedCode =
        companyCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalizedName.contains('abundance12') ||
        (normalizedName.contains('abundance') &&
            normalizedName.contains('12')) ||
        normalizedCode.contains('ABUNDANCE12') ||
        normalizedCode.contains('ABUND12') ||
        normalizedCode == 'A12' ||
        normalizedCode.startsWith('AB12');
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
            backgroundColor: const Color(0xFF050714),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1539),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF25336A)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A12 only',
                          style: TextStyle(
                            color: Color(0xFFF0D6A1),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'The My Goals experience is available for Abundance 12 company members only.',
                          style: TextStyle(
                            color: Color(0xFFB7C0E5),
                            height: 1.5,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF0B93C),
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
              backgroundColor: const Color(0xFF050714),
              body: SafeArea(
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
              'MY GOALS',
              style: TextStyle(
                color: Color(0xFFF0E6CF),
                fontSize: 28,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                fontFamily: 'Georgia',
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Personal, professional and contribution - combined into your Goal Total Score. In Todo List, new goals can include a start date and an end date.',
              style: TextStyle(
                color: Color(0xFFB7C0E5),
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
              'New goal',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF0B93C),
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
                            label: 'TOTAL GOALS',
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
                            valueColor: const Color(0xFF63E0B7),
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
                    label: 'TOTAL GOALS',
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
                    valueColor: const Color(0xFF63E0B7),
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
        color: const Color(0xFF0F173D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF27336C)),
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
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: compact ? 10 : 12,
                    backgroundColor: const Color(0xFF0A0F2B),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF6B86),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        color: Color(0xFFFF6B86),
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'of 100',
                      style: TextStyle(
                        color: Color(0xFFB7C0E5),
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
            'Goal Total Score',
            style: TextStyle(
              color: Color(0xFFF0E6CF),
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
              color: Color(0xFFB7C0E5),
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
        color: const Color(0xFF0F173D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF27336C)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F2B),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFCFD6FF),
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
                    color: Color(0xFF9EA8D6),
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
                    color: valueColor ?? const Color(0xFFF0E6CF),
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
          color: selected ? const Color(0xFF2D2744) : const Color(0xFF101737),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFF0B93C) : const Color(0xFF27336C),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          '$label  $count',
          style: TextStyle(
            color: selected ? const Color(0xFFF0B93C) : const Color(0xFFB7C0E5),
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
    if (goal.status == GoalStatus.completed) return const Color(0xFF63E0B7);
    if (goal.isOverdue) return const Color(0xFFF36D8A);
    return const Color(0xFFF0B93C);
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActionPlanItem>>(
      stream: service.watchPlans(goal.id),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const <ActionPlanItem>[];
        final completedPlans =
            plans.where((plan) => plan.status == ActionPlanStatus.done).length;
        final planLabel = plans.isEmpty
            ? 'No tasks yet'
            : '$completedPlans/${plans.length} tasks';
        final dueLabel = goal.isOverdue
            ? '${-goal.daysUntilDue}d overdue'
            : '${goal.daysUntilDue}d left';

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F173D),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFF27336C)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Badge(
                      text: goal.category.label,
                      color: Color(goal.category.accent),
                      background: const Color(0xFF241F37),
                    ),
                    _Badge(
                      text: _statusLabel(goal.status),
                      color: const Color(0xFF56C7F4),
                      background: const Color(0xFF142339),
                    ),
                    _Badge(
                      text: 'Score ${goal.progress}',
                      color: const Color(0xFFFF6B86),
                      background: const Color(0xFF2A2030),
                    ),
                    _Badge(
                      text: goal.rank.name,
                      color: const Color(0xFFCFD6FF),
                      background: const Color(0xFF232A47),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  goal.title.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFF0E6CF),
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
                      color: Color(0xFFB7C0E5),
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
                    backgroundColor: const Color(0xFF09102A),
                    valueColor: AlwaysStoppedAnimation<Color>(_progressColor),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Color(0xFF9EA8D6),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${goal.targetDate.month}/${goal.targetDate.day}/${goal.targetDate.year}  -  $dueLabel',
                        style: const TextStyle(
                          color: Color(0xFF9EA8D6),
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  planLabel,
                  style: const TextStyle(
                    color: Color(0xFF9EA8D6),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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
        color: const Color(0xFF0F173D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF27336C)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.adjust_rounded,
            size: 40,
            color: Color(0xFF9EA8D6),
          ),
          const SizedBox(height: 10),
          Text(
            hasFilter ? 'No goals in this category yet' : 'No goals yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFF0E6CF),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap New goal in Todo List to create your first A12 goal and set its start and end dates.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB7C0E5),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onNewGoal,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF0B93C),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('New goal'),
          ),
        ],
      ),
    );
  }
}
