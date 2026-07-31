import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_backdrop.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

/// Goal detail page for Abundance 12. It keeps the original actions and
/// streams, but presents them in the darker dashboard-style layout shown in
/// the mock.
class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goalId,
    required this.service,
    required this.uid,
  });

  final String goalId;
  final GoalsService service;
  final String uid;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _commentController = TextEditingController();
  final _currentValueController = TextEditingController();
  final _planEntryController = TextEditingController();
  final _currentValueFocus = FocusNode();

  @override
  void dispose() {
    _commentController.dispose();
    _currentValueController.dispose();
    _planEntryController.dispose();
    _currentValueFocus.dispose();
    super.dispose();
  }

  Future<void> _setStatus(GoalStatus status) async {
    if (status == GoalStatus.abandoned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abandon this quest?'),
          content: const Text(
            'An abandoned quest is withdrawn from your score. You can reopen it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abandon'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _runWrite(
      () => widget.service.updateGoal(
        goalId: widget.goalId,
        actorId: widget.uid,
        status: status,
      ),
      'Could not update the quest status',
    );
  }

  Future<void> _editCurrentValue(GoalSummary goal) async {
    final value = double.tryParse(_currentValueController.text.trim());
    if (value == null) return;
    final saved = await _runWrite(
      () => widget.service.setGoalMeasure(
        goalId: widget.goalId,
        actorId: widget.uid,
        currentValue: value,
      ),
      'Could not save progress',
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progress saved')),
      );
    }
  }

  Future<void> _logPeriodTarget() async {
    final logged = await _runWrite(
      () => widget.service.logMeritTarget(
        goalId: widget.goalId,
        actorId: widget.uid,
      ),
      'Could not log the period target',
    );
    if (logged && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Period target logged')),
      );
    }
  }

  Future<void> _goExtraMile() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go the extra mile'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Amount to add'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log it'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      await _runWrite(
        () => widget.service.goExtraMile(
          goalId: widget.goalId,
          actorId: widget.uid,
          amount: amount,
        ),
        'Could not log the extra mile',
      );
    }
  }

  /// Runs one mutating call and turns any failure into a visible message.
  /// Returns whether the write actually landed, so callers only show their
  /// success snackbar (or navigate) when it did.
  ///
  /// Every write on this screen goes through here. Without it a rejected
  /// write was completely invisible: a coach has read access to a mentee's
  /// quest but no write access, so the API 401s their Edit/Delete/status
  /// actions — and an unhandled rejection left the screen looking as if
  /// nothing had been tapped. This is not coach-specific; an offline device
  /// or a 500 failed exactly as silently.
  Future<bool> _runWrite(
    Future<void> Function() write,
    String failureLabel,
  ) async {
    return _reportWriteFailures(context, write, failureLabel);
  }

  Future<void> _deleteGoal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this quest?'),
        content: const Text(
          'Its tasks, comments, progress history and attachments go with it. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await _runWrite(
      () => widget.service.deleteGoal(widget.goalId),
      'Could not delete quest',
    );
    // Only leave the screen when the quest is really gone. Popping on a
    // failed delete would tell the member their quest was destroyed while
    // it is still sitting in their hub.
    if (deleted && mounted) Navigator.of(context).pop();
  }

  void _syncCurrentValue(GoalSummary goal) {
    final valueText = goal.currentValue.toStringAsFixed(
      goal.currentValue.truncateToDouble() == goal.currentValue ? 0 : 2,
    );
    if (_currentValueFocus.hasFocus) return;
    if (_currentValueController.text == valueText) return;
    _currentValueController.text = valueText;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoalSummary?>(
      stream: widget.service.watchGoal(widget.goalId),
      builder: (context, snapshot) {
        final goal = snapshot.data;
        if (goal == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        _syncCurrentValue(goal);

        return Scaffold(
          backgroundColor: _bg,
          // Same ambient hero plate the Quests hub carries — the design
          // spec scopes A12's PageBackdrop to the Quests screens rather
          // than the shell chrome every company shares.
          body: AbundanceBackdrop(
            child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1180;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BackLink(onTap: () => Navigator.of(context).maybePop()),
                          const SizedBox(height: 18),
                          _TopHeader(
                            goal: goal,
                            onStatusChanged: _setStatus,
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GoalFormScreen(
                                  service: widget.service,
                                  uid: widget.uid,
                                  existing: goal,
                                ),
                              ),
                            ),
                            onDelete: _deleteGoal,
                          ),
                          const SizedBox(height: 20),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      _GoalScoreCard(
                                        goal: goal,
                                        goalId: widget.goalId,
                                        service: widget.service,
                                        currentValueController:
                                            _currentValueController,
                                        currentValueFocus: _currentValueFocus,
                                        onSave: goal.goalType == GoalType.merit
                                            ? () => _editCurrentValue(goal)
                                            : null,
                                        onExtraMile: goal.goalType ==
                                                GoalType.merit
                                            ? _goExtraMile
                                            : null,
                                        onLogPeriodTarget: goal.goalType ==
                                                    GoalType.merit &&
                                                goal.targetPeriod !=
                                                    TargetPeriod.none
                                            ? _logPeriodTarget
                                            : null,
                                      ),
                                      const SizedBox(height: 18),
                                      _ActionPlansCard(
                                        goalId: widget.goalId,
                                        service: widget.service,
                                        uid: widget.uid,
                                        planEntryController:
                                            _planEntryController,
                                      ),
                                      const SizedBox(height: 18),
                                      _CommentsCard(
                                        goalId: widget.goalId,
                                        service: widget.service,
                                        uid: widget.uid,
                                        controller: _commentController,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 18),
                                SizedBox(
                                  width: 540,
                                  child: Column(
                                    children: [
                                      _ProgressHistoryCard(
                                        goalId: widget.goalId,
                                        service: widget.service,
                                      ),
                                      const SizedBox(height: 18),
                                      _AttachmentsCard(goal: goal),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _GoalScoreCard(
                                  goal: goal,
                                  goalId: widget.goalId,
                                  service: widget.service,
                                  currentValueController:
                                      _currentValueController,
                                  currentValueFocus: _currentValueFocus,
                                  onSave: goal.goalType == GoalType.merit
                                      ? () => _editCurrentValue(goal)
                                      : null,
                                  onExtraMile: goal.goalType == GoalType.merit
                                      ? _goExtraMile
                                      : null,
                                  onLogPeriodTarget: goal.goalType ==
                                                  GoalType.merit &&
                                              goal.targetPeriod !=
                                                  TargetPeriod.none
                                      ? _logPeriodTarget
                                      : null,
                                ),
                                const SizedBox(height: 18),
                                _ActionPlansCard(
                                  goalId: widget.goalId,
                                  service: widget.service,
                                  uid: widget.uid,
                                  planEntryController: _planEntryController,
                                ),
                                const SizedBox(height: 18),
                                _CommentsCard(
                                  goalId: widget.goalId,
                                  service: widget.service,
                                  uid: widget.uid,
                                  controller: _commentController,
                                ),
                                const SizedBox(height: 18),
                                _ProgressHistoryCard(
                                  goalId: widget.goalId,
                                  service: widget.service,
                                ),
                                const SizedBox(height: 18),
                                _AttachmentsCard(goal: goal),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ),
        );
      },
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, color: _muted, size: 22),
            SizedBox(width: 6),
            Text(
              'My quests',
              style: TextStyle(
                color: _muted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.goal,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final GoalSummary goal;
  final Future<void> Function(GoalStatus status) onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 760;
        final controls = stacked
            ? Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatusDropdown(
                    value: goal.status,
                    onChanged: onStatusChanged,
                  ),
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    onTap: onEdit,
                  ),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, color: _danger, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Delete',
                            style: TextStyle(
                              color: _danger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusDropdown(
                    value: goal.status,
                    onChanged: onStatusChanged,
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, color: _danger, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Delete',
                            style: TextStyle(
                              color: _danger,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              controls,
              const SizedBox(height: 16),
            ] else
              Align(alignment: Alignment.centerRight, child: controls),
            const SizedBox(height: 12),
            Text(
              goal.title.toUpperCase(),
              style: const TextStyle(
                color: _text,
                fontSize: 28,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                fontFamily: 'Georgia',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Badge(
                  label: goal.category.label,
                  background: AbundanceColors.categoryColor(goal.category.code)
                      .withValues(alpha: 0.12),
                  foreground: AbundanceColors.categoryColor(goal.category.code),
                ),
                _Badge(
                  label: goal.status.label,
                  background: _statusBackground(goal.status),
                  foreground: _statusForeground(goal.status),
                ),
                _Badge(
                  label: 'Score ${goal.progress}',
                  background: AbundanceColors.scoreColorFor(goal.progress)
                      .withValues(alpha: 0.12),
                  foreground: AbundanceColors.scoreColorFor(goal.progress),
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
                      label: goal.rank.name,
                      background: _chipGrayBg,
                      foreground: _chipGray,
                    ),
                  ],
                ),
                _MetaPill(
                  icon: Icons.calendar_today_outlined,
                  text:
                      'Target ${DateFormat('MMM d, yyyy').format(goal.targetDate)}',
                ),
                _MetaPill(
                  icon: Icons.timelapse_rounded,
                  text: goal.isOverdue
                      ? '${-goal.daysUntilDue}d overdue'
                      : '${goal.daysUntilDue}d left',
                ),
              ],
            ),
            if ((goal.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                goal.description!,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _GoalScoreCard extends StatelessWidget {
  const _GoalScoreCard({
    required this.goal,
    required this.goalId,
    required this.service,
    required this.currentValueController,
    required this.currentValueFocus,
    required this.onSave,
    required this.onExtraMile,
    required this.onLogPeriodTarget,
  });

  final GoalSummary goal;
  final String goalId;
  final GoalsService service;
  final TextEditingController currentValueController;
  final FocusNode currentValueFocus;
  final VoidCallback? onSave;
  final VoidCallback? onExtraMile;
  final VoidCallback? onLogPeriodTarget;

  @override
  Widget build(BuildContext context) {
    final hasTarget = goal.targetValue > 0;
    final isMerit = goal.goalType == GoalType.merit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quest Score',
            style: TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'How far your current value has come toward the target.',
            style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 6),
          const Text(
            'Quests only earn full score when they\'re finished by the target date.',
            style: TextStyle(color: _muted, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 640;
              final circle = _ScoreCircle(score: goal.progress);
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMerit)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'This quest is scored by its action plans.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 14.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (isMerit) ...[
                    Text(
                      hasTarget
                          ? '${goal.currentValue.toStringAsFixed(
                              goal.currentValue.truncateToDouble() == goal.currentValue ? 0 : 2,
                            )} / ${goal.targetValue.toStringAsFixed(
                              goal.targetValue.truncateToDouble() == goal.targetValue ? 0 : 2,
                            )} ${goal.unit}'.trim()
                      : 'No measure set yet — add a target to start scoring this quest.',
                      style: const TextStyle(
                        color: _text,
                        fontSize: 15.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: (goal.progress / 100).clamp(0.0, 1.0),
                        backgroundColor: _barBg,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, innerConstraints) {
                        final stacked = innerConstraints.maxWidth < 600;
                        final currentInput = SizedBox(
                          width: stacked ? double.infinity : 160,
                          child: TextField(
                            controller: currentValueController,
                            focusNode: currentValueFocus,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              color: _text,
                              fontSize: 15,
                            ),
                            decoration: _numberDecoration(),
                          ),
                        );
                        final saveButton = FilledButton(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: _buttonDark,
                            foregroundColor: _text,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Save'),
                        );
                        final extraButton = TextButton(
                          onPressed: onExtraMile,
                          style: TextButton.styleFrom(
                            foregroundColor: _text,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: const Text('Go extra mile'),
                        );
                        final logTargetButton = TextButton(
                          onPressed: onLogPeriodTarget,
                          style: TextButton.styleFrom(
                            foregroundColor: AbundanceColors.accentCyan,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: const Text('Log period target'),
                        );
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              currentInput,
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  saveButton,
                                  if (onExtraMile != null) extraButton,
                                  if (onLogPeriodTarget != null)
                                    logTargetButton,
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const Text(
                              'Current',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 10),
                            currentInput,
                            const SizedBox(width: 10),
                            saveButton,
                            if (onExtraMile != null) ...[
                              const SizedBox(width: 8),
                              extraButton,
                            ],
                            if (onLogPeriodTarget != null) ...[
                              const SizedBox(width: 8),
                              logTargetButton,
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              );

              if (narrow) {
                return Column(
                  children: [
                    circle,
                    const SizedBox(height: 20),
                    details,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  circle,
                  const SizedBox(width: 22),
                  Expanded(child: details),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const Divider(color: _divider, height: 1),
          const SizedBox(height: 14),
          StreamBuilder<List<ActionPlanItem>>(
            stream: service.watchPlans(goalId),
            builder: (context, snapshot) {
              final plans = snapshot.data ?? const <ActionPlanItem>[];
              final doneCount = plans
                  .where((plan) => plan.status == ActionPlanStatus.done)
                  .length;
              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _DetailStat(
                    label: 'Started',
                    value: DateFormat('MMM d, yyyy').format(goal.startDate),
                  ),
                  _DetailStat(
                    label: 'Target date',
                    value: DateFormat('MMM d, yyyy').format(goal.targetDate),
                  ),
                  _DetailStat(
                    label: 'Completed',
                    value: goal.completedAt == null
                        ? '—'
                        : DateFormat('MMM d, yyyy').format(goal.completedAt!),
                  ),
                  _DetailStat(
                    label: 'Action plans',
                    value: '$doneCount/${plans.length} done',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionPlansCard extends StatelessWidget {
  const _ActionPlansCard({
    required this.goalId,
    required this.service,
    required this.uid,
    required this.planEntryController,
  });

  final String goalId;
  final GoalsService service;
  final String uid;
  final TextEditingController planEntryController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: StreamBuilder<List<ActionPlanItem>>(
        stream: service.watchPlans(goalId),
        builder: (context, snapshot) {
          final plans = snapshot.data ?? const <ActionPlanItem>[];
          final doneCount =
              plans.where((plan) => plan.status == ActionPlanStatus.done).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Action Plans',
                      style: TextStyle(
                        color: _text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Georgia',
                      ),
                    ),
                  ),
                  Text(
                    '$doneCount/${plans.length} done',
                    style: const TextStyle(color: _muted, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'The steps toward this quest. Click a status to move it between not started, in progress and done.',
                style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (plans.isEmpty)
                const _EmptySectionBody(
                  icon: Icons.list_alt_rounded,
                  title: 'No action plans yet',
                  subtitle: 'Add a plan below to start tracking the work.',
                )
              else
                Column(
                  children: [
                    for (final plan in plans) ...[
                      _ActionPlanRow(
                        plan: plan,
                        onCycleStatus: () => _reportWriteFailures(
                          context,
                          () => service.setActionPlanStatus(
                            goalId: goalId,
                            planId: plan.id,
                            status: plan.status.next,
                            actorId: uid,
                          ),
                          'Could not update the action plan',
                        ),
                        onDelete: () => _reportWriteFailures(
                          context,
                          () => service.deleteActionPlan(
                            goalId: goalId,
                            planId: plan.id,
                            actorId: uid,
                          ),
                          'Could not delete the action plan',
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 520;
                  final input = TextField(
                    controller: planEntryController,
                    style: const TextStyle(color: _text, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Add an action plan...',
                      hintStyle: TextStyle(color: _muted, fontSize: 14),
                    ),
                  );
                  final addButton = FilledButton.icon(
                    onPressed: () {
                      final text = planEntryController.text.trim();
                      if (text.isEmpty) return;
                      _reportWriteFailures(
                        context,
                        () => service.addActionPlan(
                          goalId: goalId,
                          title: text,
                          actorId: uid,
                        ),
                        'Could not add the action plan',
                      );
                      planEntryController.clear();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _buttonDark,
                      foregroundColor: _text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        input,
                        const SizedBox(height: 10),
                        addButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: input),
                      const SizedBox(width: 10),
                      addButton,
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommentsCard extends StatelessWidget {
  const _CommentsCard({
    required this.goalId,
    required this.service,
    required this.uid,
    required this.controller,
  });

  final String goalId;
  final GoalsService service;
  final String uid;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: StreamBuilder<List<GoalCommentItem>>(
        stream: service.watchComments(goalId),
        builder: (context, snapshot) {
          final comments = snapshot.data ?? const <GoalCommentItem>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
              'Comments',
              style: TextStyle(
                color: _text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFamily: 'Georgia',
              ),
            ),
              const SizedBox(height: 10),
              const Text(
                'Your coach\'s feedback, and your replies.',
                style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              if (comments.isEmpty)
                const _EmptySectionBody(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No comments yet',
                  subtitle: 'Start the thread and your coach gets a notification.',
                )
              else
                Column(
                  children: [
                    for (final comment in comments.take(6))
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _innerPanel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _innerBorder),
                        ),
                        child: Text(
                          comment.body,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                style: const TextStyle(color: _text, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ask a question, log a reflection, or reply to your coach...',
                  hintStyle: TextStyle(color: _muted, fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    final body = controller.text.trim();
                    if (body.isEmpty) return;
                    _reportWriteFailures(
                      context,
                      () => service.addComment(
                        goalId: goalId,
                        authorId: uid,
                        body: body,
                      ),
                      'Could not post the comment',
                    );
                    controller.clear();
                  },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Post comment'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressHistoryCard extends StatelessWidget {
  const _ProgressHistoryCard({
    required this.goalId,
    required this.service,
  });

  final String goalId;
  final GoalsService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: StreamBuilder<List<GoalUpdateEntry>>(
        stream: service.watchUpdates(goalId),
        builder: (context, snapshot) {
          final updates = snapshot.data ?? const <GoalUpdateEntry>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
            'Progress History',
            style: TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
              const SizedBox(height: 8),
          const Text(
            'Every movement, in order.',
            style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
          ),
              const SizedBox(height: 14),
              if (updates.isEmpty)
                const _EmptySectionBody(
                  icon: Icons.trending_up_rounded,
                  title: 'No movement yet',
                  subtitle: 'Tick a task or change the status and it shows up here.',
                )
              else
                Column(
                  children: [
                    for (final update in updates.take(12))
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _innerPanel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _innerBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              update.statusFrom != update.statusTo
                                  ? '${update.statusFrom.label} → ${update.statusTo.label}'
                                  : 'Progress update',
                                style: const TextStyle(
                                  color: _text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${update.progressFrom}% → ${update.progressTo}%',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                            ),
                            if (update.createdAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                DateFormat('MMM d, yyyy • h:mm a')
                                    .format(update.createdAt!),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({required this.goal});

  final GoalSummary goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachments',
            style: TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Proof, plans and references.',
            style: TextStyle(color: _muted, fontSize: 14.5, height: 1.45),
          ),
          SizedBox(height: 14),
          _EmptySectionBody(
            icon: Icons.flag_outlined,
            title: 'Nothing attached',
            subtitle: 'Files linked to this quest will appear here.',
          ),
        ],
      ),
    );
  }
}

class _ActionPlanRow extends StatelessWidget {
  const _ActionPlanRow({
    required this.plan,
    required this.onCycleStatus,
    required this.onDelete,
  });

  final ActionPlanItem plan;
  final VoidCallback onCycleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chipColor = switch (plan.status) {
      ActionPlanStatus.notStarted => _muted,
      ActionPlanStatus.inProgress => _chipBlue,
      ActionPlanStatus.done => _chipGreen,
    };

    return InkWell(
      onTap: onCycleStatus,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _innerPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _innerBorder),
        ),
        child: Row(
          children: [
            _Badge(
              label: plan.status.label,
              background: chipColor.withValues(alpha: 0.12),
              foreground: chipColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plan.title,
                style: const TextStyle(
                  color: _text,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ),
            IconButton(
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.close, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySectionBody extends StatelessWidget {
  const _EmptySectionBody({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: _emptyPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _innerBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: _circleBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _muted, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
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
              color: _muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  const _ScoreCircle({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    final size = compact ? 146.0 : 170.0;
    final scoreColor = AbundanceColors.scoreColorFor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: compact ? 10 : 12,
              backgroundColor: _barBg,
              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 40,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'of 100',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.value,
    required this.onChanged,
  });

  final GoalStatus value;
  final Future<void> Function(GoalStatus status) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GoalStatus>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 18),
          dropdownColor: _panel,
          style: const TextStyle(
            color: _text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final status in GoalStatus.values)
              DropdownMenuItem(
                value: status,
                child: Text(status.label),
              ),
          ],
          onChanged: (status) {
            if (status == null || status == value) return;
            onChanged(status);
          },
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _text, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: _metaBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _muted),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared by [_GoalDetailScreenState._runWrite] and by the stateless cards
/// below, which issue their own writes (action plans, comments) and were
/// just as silent on failure. One implementation so every write on this
/// screen fails the same visible way, with the same wording shape the quest
/// wizard already uses ('Could not save quest: $e').
Future<bool> _reportWriteFailures(
  BuildContext context,
  Future<void> Function() write,
  String failureLabel,
) async {
  try {
    await write();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failureLabel: $e')),
      );
    }
    return false;
  }
}

InputDecoration _numberDecoration() {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: _innerPanel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _innerBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _innerBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _accent, width: 1.4),
    ),
  );
}

Color _statusBackground(GoalStatus status) {
  return switch (status) {
    GoalStatus.notStarted => _chipGrayBg,
    GoalStatus.inProgress => _chipBlueBg,
    GoalStatus.atRisk => _chipPinkBg,
    GoalStatus.completed => _chipGreenBg,
    GoalStatus.abandoned => _dangerBg,
  };
}

Color _statusForeground(GoalStatus status) {
  return switch (status) {
    GoalStatus.notStarted => _chipGray,
    GoalStatus.inProgress => _chipBlue,
    GoalStatus.atRisk => _chipPink,
    GoalStatus.completed => _chipGreen,
    GoalStatus.abandoned => _danger,
  };
}

// Sourced from AbundanceColors (lib/src/features/abundance/theme/abundance_theme.dart)
// rather than new magic hex — this screen's own dark dashboard palette was
// built before that shared token file existed; these aliases keep the rest
// of this file's widget code unchanged while pointing every solid color at
// the single shared source of truth. The "*Bg" variants below are subtle
// tinted backgrounds with no AbundanceColors equivalent (status chips and
// plan-row chips only, out of this task's explicit color-mapping scope) and
// remain as they were.
const Color _bg = AbundanceColors.background;
const Color _panel = AbundanceColors.surfaceRaised;
const Color _innerPanel = AbundanceColors.surfaceSunken;
const Color _emptyPanel = AbundanceColors.surfaceSunken;
const Color _border = AbundanceColors.border;
const Color _innerBorder = AbundanceColors.border;
const Color _divider = AbundanceColors.border;
const Color _text = AbundanceColors.foreground;
const Color _muted = AbundanceColors.muted;
const Color _accent = AbundanceColors.primaryGold;
const Color _accentGold = AbundanceColors.primaryGold;
const Color _buttonDark = AbundanceColors.surfaceSunken;
const Color _barBg = AbundanceColors.surfaceSunken;
const Color _circleBg = AbundanceColors.surfaceSunken;
const Color _metaBg = AbundanceColors.surfaceSunken;
const Color _danger = AbundanceColors.scoreCritical;
const Color _dangerBg = Color(0xFF2A1230);
const Color _chipPink = AbundanceColors.scoreCritical;
const Color _chipPinkBg = Color(0xFF2A2030);
const Color _chipBlue = AbundanceColors.accentCyan;
const Color _chipBlueBg = Color(0xFF142339);
const Color _chipGreen = AbundanceColors.scoreExcellent;
const Color _chipGreenBg = Color(0xFF12302A);
const Color _chipGray = AbundanceColors.muted;
const Color _chipGrayBg = Color(0xFF232A47);
