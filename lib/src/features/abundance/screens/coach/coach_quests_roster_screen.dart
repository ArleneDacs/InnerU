import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

/// Read-only: every mentee this coach is assigned, with their quests,
/// mirroring `A12-Tracker`'s `coach/goals` page — one card per mentee,
/// grouped, with a "Quest Score" summary and each quest linking out to
/// [GoalDetailScreen]. This file makes no create/update/delete call against
/// [GoalsService] anywhere; it only reads via [GoalsService.fetchCoachGoalsRoster].
///
/// The reference page filters via server-side query params (council,
/// category, score). This screen only has the already-fetched roster to
/// work with, so filtering here is client-side, over that one response —
/// currently just the student-name search, mirroring the reference's
/// "Student" filter field.
class CoachQuestsRosterScreen extends StatefulWidget {
  const CoachQuestsRosterScreen({
    super.key,
    required this.service,
    required this.coachUid,
  });

  final GoalsService service;
  final String coachUid;

  @override
  State<CoachQuestsRosterScreen> createState() =>
      _CoachQuestsRosterScreenState();
}

class _CoachQuestsRosterScreenState extends State<CoachQuestsRosterScreen> {
  late final Future<List<CoachMenteeGoals>> _rosterFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rosterFuture = widget.service.fetchCoachGoalsRoster();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  void _openGoal(CoachMenteeGoals entry, String goalId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(
          goalId: goalId,
          service: widget.service,
          // The mentee this quest belongs to, never the coach — writes made
          // from GoalDetailScreen (status changes, comments, measures) must
          // be attributed to the mentee whose quest it is.
          uid: entry.menteeId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbundanceColors.background,
      body: SafeArea(
        child: FutureBuilder<List<CoachMenteeGoals>>(
          future: _rosterFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AbundanceColors.primaryGold,
                ),
              );
            }

            final roster = snapshot.data!;
            final query = _searchQuery.trim().toLowerCase();
            final filtered = query.isEmpty
                ? roster
                : roster
                    .where((entry) =>
                        entry.menteeName.toLowerCase().contains(query))
                    .toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RosterHeader(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 20),
                      if (roster.isEmpty)
                        const _RosterEmptyState(
                          title: 'No students yet',
                          subtitle:
                              'No student in the organization is visible to you yet.',
                        )
                      else if (filtered.isEmpty)
                        _RosterEmptyState(
                          title: 'Nothing matches this search',
                          subtitle:
                              'No student matches "${_searchQuery.trim()}". Try another name.',
                          onClear: _clearSearch,
                        )
                      else
                        for (final entry in filtered) ...[
                          _MenteeQuestsGroup(
                            entry: entry,
                            onOpenGoal: (goalId) => _openGoal(entry, goalId),
                          ),
                          const SizedBox(height: 16),
                        ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RosterHeader extends StatelessWidget {
  const _RosterHeader({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quests',
          style: TextStyle(
            color: AbundanceColors.foreground,
            fontSize: 28,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            fontFamily: 'Georgia',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Every student's quests on one page, grouped by student. Tap a "
          'quest to open it.',
          style: TextStyle(
            color: AbundanceColors.muted,
            fontSize: 15.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: AbundanceColors.foreground),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AbundanceColors.surfaceSunken,
              hintText: 'Search by student name',
              hintStyle: const TextStyle(color: AbundanceColors.muted),
              prefixIcon:
                  const Icon(Icons.search, color: AbundanceColors.muted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AbundanceColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AbundanceColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AbundanceColors.primaryGold,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RosterEmptyState extends StatelessWidget {
  const _RosterEmptyState({
    required this.title,
    required this.subtitle,
    this.onClear,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AbundanceColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AbundanceColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.groups_outlined,
            size: 40,
            color: AbundanceColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AbundanceColors.muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onClear,
              child: const Text(
                'Clear search',
                style: TextStyle(
                  color: AbundanceColors.primaryGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One roster row: a mentee's name, their combined Quest Score, and every
/// quest they hold. Mirrors the `<details>` group in `coach/goals/page.tsx`,
/// minus the collapse/expand affordance (always expanded here) since there's
/// no per-mentee state worth persisting in this read-only view.
class _MenteeQuestsGroup extends StatelessWidget {
  const _MenteeQuestsGroup({required this.entry, required this.onOpenGoal});

  final CoachMenteeGoals entry;
  final ValueChanged<String> onOpenGoal;

  /// The Goal Total Score for this mentee, computed the same way
  /// `GoalsHubScreen` computes a mentee's own overall score: abandoned
  /// quests withdrawn, categories averaged, then equally weighted.
  double _questScore() {
    final activeGoals =
        entry.goals.where((g) => g.status != GoalStatus.abandoned).toList();
    final scorable = activeGoals
        .map((g) => ScorableGoal(
              status: g.status,
              progress: g.progress,
              category: g.category,
              goalType: g.goalType,
              targetValue: g.targetValue,
              currentValue: g.currentValue,
            ))
        .toList();
    return weightGoalScore(scoreCategories(scorable));
  }

  @override
  Widget build(BuildContext context) {
    final gaps = requiredGoalGaps(entry.goals);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AbundanceColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AbundanceColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MenteeAvatar(name: entry.menteeName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.menteeName,
                        style: const TextStyle(
                          color: AbundanceColors.foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Georgia',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Quest Score ',
                            style: TextStyle(
                              color: AbundanceColors.muted,
                              fontSize: 13.5,
                            ),
                          ),
                          TextSpan(
                            text: _formatScore(_questScore()),
                            style: const TextStyle(
                              color: AbundanceColors.foreground,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Mirrors `coach/goals/page.tsx`'s per-mentee "No {category}
                // quest" danger badges in the group summary row: one
                // _MiniBadge per category with no live goal, computed
                // client-side from this mentee's own `goals` — the same
                // `requiredGoalGaps` helper the mentee-facing dashboards
                // already use to flag their own gaps.
                if (gaps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final category in gaps)
                        _MiniBadge(
                          label: 'No ${category.label} quest',
                          color: AbundanceColors.scoreCritical,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AbundanceColors.border),
          if (entry.goals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No quests set yet.',
                style: TextStyle(color: AbundanceColors.muted, fontSize: 14),
              ),
            )
          else
            Column(
              children: [
                for (final goal in entry.goals)
                  _QuestRow(goal: goal, onTap: () => onOpenGoal(goal.id)),
              ],
            ),
        ],
      ),
    );
  }
}

class _MenteeAvatar extends StatelessWidget {
  const _MenteeAvatar({required this.name});

  final String name;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AbundanceColors.surfaceSunken,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: const TextStyle(
          color: AbundanceColors.primaryGold,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// One quest, read-only. Mirrors the goal row in `coach/goals/page.tsx`:
/// status, category, a score badge, a progress bar and a due/overdue label.
class _QuestRow extends StatelessWidget {
  const _QuestRow({required this.goal, required this.onTap});

  final GoalSummary goal;
  final VoidCallback onTap;

  Color _statusColor(GoalStatus status) {
    return switch (status) {
      GoalStatus.notStarted => AbundanceColors.muted,
      GoalStatus.inProgress => AbundanceColors.accentCyan,
      GoalStatus.atRisk => AbundanceColors.scoreCritical,
      GoalStatus.completed => AbundanceColors.scoreExcellent,
      GoalStatus.abandoned => AbundanceColors.scoreCritical,
    };
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = AbundanceColors.categoryColor(goal.category.code);
    final statusColor = _statusColor(goal.status);
    final score = goal.score;
    final scoreColor =
        score == null ? AbundanceColors.muted : AbundanceColors.scoreColorFor(score);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AbundanceColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: const TextStyle(
                          color: AbundanceColors.foreground,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        goal.category.label,
                        style: TextStyle(
                          color: categoryColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MiniBadge(label: goal.status.label, color: statusColor),
                    _MiniBadge(
                      label: score == null
                          ? 'Score —'
                          : 'Score ${_formatScore(score)}',
                      color: scoreColor,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (goal.progress / 100).clamp(0.0, 1.0),
                backgroundColor: AbundanceColors.surfaceSunken,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AbundanceColors.scoreColorFor(goal.progress),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              goal.isOverdue
                  ? 'Overdue · ${DateFormat('MMM d, yyyy').format(goal.targetDate)}'
                  : 'Due ${DateFormat('MMM d, yyyy').format(goal.targetDate)}',
              style: TextStyle(
                color: goal.isOverdue
                    ? AbundanceColors.scoreCritical
                    : AbundanceColors.muted,
                fontSize: 12,
                fontWeight: goal.isOverdue ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Mirrors A12's `formatScore`: an integer score has no decimal, a
/// fractional one gets exactly one, and every score carries a `%` — the
/// reader should never have to guess the unit.
String _formatScore(num score) {
  final isWhole = score == score.roundToDouble();
  final text = isWhole ? score.toStringAsFixed(0) : score.toStringAsFixed(1);
  return '$text%';
}
