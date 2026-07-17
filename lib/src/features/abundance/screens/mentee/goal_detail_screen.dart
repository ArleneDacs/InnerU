import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// One goal, in full: measure panel (MERIT) or informational plan completion
/// (MILESTONE), action plans, status controls, updates ledger, comments.
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

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(GoalStatus status) async {
    if (status == GoalStatus.abandoned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abandon this goal?'),
          content: const Text(
              'An abandoned goal is withdrawn from your score — it does not '
              'count as zero. You can reopen it later.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abandon')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.service.updateGoal(
        goalId: widget.goalId, actorId: widget.uid, status: status);
  }

  Future<void> _editCurrentValue(GoalSummary goal) async {
    final controller =
        TextEditingController(text: goal.currentValue.toString());
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Current ${goal.unit.isEmpty ? 'value' : goal.unit}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      await widget.service.setGoalMeasure(
          goalId: widget.goalId, actorId: widget.uid, currentValue: value);
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
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log it'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      await widget.service.goExtraMile(
          goalId: widget.goalId, actorId: widget.uid, amount: amount);
    }
  }

  Future<void> _deleteGoal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: const Text('This permanently removes the goal, its plans, '
            'updates, and comments.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.service.deleteGoal(widget.goalId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoalSummary?>(
      stream: widget.service.watchGoal(widget.goalId),
      builder: (context, snapshot) {
        final goal = snapshot.data;
        if (goal == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(goal.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GoalFormScreen(
                      service: widget.service,
                      uid: widget.uid,
                      existing: goal,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<GoalStatus>(
                onSelected: _setStatus,
                itemBuilder: (context) => [
                  for (final s in GoalStatus.values)
                    if (s != goal.status)
                      PopupMenuItem(value: s, child: Text(s.label)),
                ],
                icon: const Icon(Icons.flag_outlined),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteGoal,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(goal: goal),
              const SizedBox(height: 16),
              if (goal.goalType == GoalType.merit)
                _MeasurePanel(
                  goal: goal,
                  service: widget.service,
                  uid: widget.uid,
                  onEditValue: () => _editCurrentValue(goal),
                  onExtraMile: _goExtraMile,
                ),
              const SizedBox(height: 16),
              _PlansPanel(
                  goalId: widget.goalId,
                  service: widget.service,
                  uid: widget.uid),
              const SizedBox(height: 16),
              _CommentsPanel(
                goalId: widget.goalId,
                service: widget.service,
                uid: widget.uid,
                controller: _commentController,
              ),
              const SizedBox(height: 16),
              _UpdatesPanel(goalId: widget.goalId, service: widget.service),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.goal});

  final GoalSummary goal;

  @override
  Widget build(BuildContext context) {
    final accent = Color(goal.category.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Chip(
              label: Text(goal.category.label,
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: accent.withValues(alpha: 0.2),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(goal.status.label,
                  style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if ((goal.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(goal.description!),
        ],
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: goal.progress / 100,
          color: accent,
          backgroundColor: accent.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 6),
        Text(
          '${goal.rank.name} · ${goal.progress}% · '
          '${goal.isOverdue ? "overdue" : "${goal.daysUntilDue} days left"}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _MeasurePanel extends StatelessWidget {
  const _MeasurePanel({
    required this.goal,
    required this.service,
    required this.uid,
    required this.onEditValue,
    required this.onExtraMile,
  });

  final GoalSummary goal;
  final GoalsService service;
  final String uid;
  final VoidCallback onEditValue;
  final VoidCallback onExtraMile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MeritLogItem>>(
      stream: service.watchMerits(goal.id),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const <MeritLogItem>[];
        final logged =
            periodLogged(logs.map((l) => l.date), goal.targetPeriod);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Measure', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  '${goal.currentValue} / ${goal.targetValue} ${goal.unit}'
                      .trim(),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (goal.targetPeriod != TargetPeriod.none) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${goal.targetPeriod.label}: '
                    '${goal.periodTarget} ${goal.unit}'.trim(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (goal.targetPeriod != TargetPeriod.none)
                      FilledButton.tonal(
                        key: const Key('log-period-target'),
                        onPressed: logged
                            ? null
                            : () => service.logMeritTarget(
                                goalId: goal.id, actorId: uid),
                        child: Text(
                            logged ? 'Logged this period' : 'Log period target'),
                      ),
                    OutlinedButton(
                      onPressed: onExtraMile,
                      child: const Text('Go extra mile'),
                    ),
                    TextButton(
                      onPressed: onEditValue,
                      child: const Text('Edit value'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlansPanel extends StatelessWidget {
  const _PlansPanel({
    required this.goalId,
    required this.service,
    required this.uid,
  });

  final String goalId;
  final GoalsService service;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final entry = TextEditingController();
    return StreamBuilder<List<ActionPlanItem>>(
      stream: service.watchPlans(goalId),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const <ActionPlanItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Action plans',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final plan in plans)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (plan.status) {
                        ActionPlanStatus.done => Icons.check_circle,
                        ActionPlanStatus.inProgress => Icons.timelapse,
                        ActionPlanStatus.notStarted =>
                          Icons.radio_button_unchecked,
                      },
                      color: plan.status == ActionPlanStatus.done
                          ? Colors.green
                          : null,
                    ),
                    title: Text(plan.title),
                    subtitle: Text(plan.status.label,
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => service.setActionPlanStatus(
                      goalId: goalId,
                      planId: plan.id,
                      status: plan.status.next,
                      actorId: uid,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => service.deleteActionPlan(
                          goalId: goalId, planId: plan.id, actorId: uid),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: entry,
                        decoration: const InputDecoration(
                            hintText: 'Add a plan step', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final t = entry.text.trim();
                        if (t.isEmpty) return;
                        service.addActionPlan(
                            goalId: goalId, title: t, actorId: uid);
                        entry.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommentsPanel extends StatelessWidget {
  const _CommentsPanel({
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
    return StreamBuilder<List<GoalCommentItem>>(
      stream: service.watchComments(goalId),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? const <GoalCommentItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comments',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final comment in comments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(comment.body),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            hintText: 'Add a comment', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: () {
                        final body = controller.text.trim();
                        if (body.isEmpty) return;
                        service.addComment(
                            goalId: goalId, authorId: uid, body: body);
                        controller.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UpdatesPanel extends StatelessWidget {
  const _UpdatesPanel({required this.goalId, required this.service});

  final String goalId;
  final GoalsService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GoalUpdateEntry>>(
      stream: service.watchUpdates(goalId),
      builder: (context, snapshot) {
        final updates = snapshot.data ?? const <GoalUpdateEntry>[];
        if (updates.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('History', style: Theme.of(context).textTheme.titleSmall),
                for (final update in updates.take(15))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      update.statusFrom != update.statusTo
                          ? '${update.statusFrom.label} → '
                              '${update.statusTo.label} · '
                              '${update.progressFrom}% → ${update.progressTo}%'
                          : '${update.progressFrom}% → ${update.progressTo}%',
                      style: const TextStyle(fontSize: 12),
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
