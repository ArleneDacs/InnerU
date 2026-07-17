import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// The mentee's goals hub: one tab per required life category, goal cards
/// with progress bars and rank medals, and a banner naming the categories
/// still missing a goal.
class GoalsHubScreen extends StatefulWidget {
  const GoalsHubScreen({super.key, this.service, this.uid});

  /// Injectable for tests; production falls back to the real instances.
  final GoalsService? service;
  final String? uid;

  @override
  State<GoalsHubScreen> createState() => _GoalsHubScreenState();
}

class _GoalsHubScreenState extends State<GoalsHubScreen> {
  late final GoalsService _service;
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalsService(FirebaseFirestore.instance);
    _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  // Replaced by Task 8 (form) and Task 9 (detail).
  void _openForm({GoalSummary? existing}) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goal form coming in the next step')),
    );
  }

  void _openDetail(GoalSummary goal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(goal.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: GoalCategory.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Goals'),
          bottom: TabBar(
            tabs: [
              for (final category in GoalCategory.values)
                Tab(text: category.label),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openForm(),
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<List<GoalSummary>>(
          stream: _service.watchGoals(_uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final goals = snapshot.data!;
            final gaps = requiredGoalGaps(goals);
            return Column(
              children: [
                if (gaps.isNotEmpty) _GapsBanner(gaps: gaps),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final category in GoalCategory.values)
                        _GoalList(
                          goals: goals
                              .where((g) => g.category == category)
                              .toList(),
                          onTap: _openDetail,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GapsBanner extends StatelessWidget {
  const _GapsBanner({required this.gaps});

  final List<GoalCategory> gaps;

  @override
  Widget build(BuildContext context) {
    final names = gaps.map((g) => g.label).join(' and ');
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: Text(
        'All three areas need a goal — you have none in $names yet. '
        'An empty area scores zero.',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.goals, required this.onTap});

  final List<GoalSummary> goals;
  final void Function(GoalSummary) onTap;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      return const Center(
        child: Text('No goals here yet. Tap + to set one.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: goals.length,
      itemBuilder: (context, index) => _GoalCard(
        goal: goals[index],
        onTap: () => onTap(goals[index]),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});

  final GoalSummary goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(goal.category.accent);
    final due = goal.isOverdue
        ? 'Overdue by ${-goal.daysUntilDue} days'
        : 'Due in ${goal.daysUntilDue} days';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  Chip(
                    label: Text(goal.status.label,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: goal.progress / 100,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${goal.rank.name} · ${goal.progress}%',
                      style: const TextStyle(fontSize: 12)),
                  Text(
                    due,
                    style: TextStyle(
                      fontSize: 12,
                      color: goal.isOverdue ? Colors.red : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
