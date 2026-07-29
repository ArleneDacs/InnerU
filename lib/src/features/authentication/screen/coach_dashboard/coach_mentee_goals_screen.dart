import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart'
    show
        Task,
        TaskTag,
        TaskTagExtension,
        taskProgress,
        taskIsEffectivelyCompleted;
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

/// Read-only view of a mentee's goals (the same list/scoring shown on their
/// own Goals screen in todo_list.dart) for a coach to check in on - reuses
/// Task/taskProgress/taskIsEffectivelyCompleted directly so the numbers
/// here always match what the mentee sees, rather than a separate
/// approximation drifting out of sync.
class CoachMenteeGoalsScreen extends StatelessWidget {
  const CoachMenteeGoalsScreen({
    super.key,
    required this.menteeName,
    required this.tasks,
  });

  final String menteeName;
  final List<Task> tasks;

  int get _completedCount => tasks.where(taskIsEffectivelyCompleted).length;

  int get _score {
    if (tasks.isEmpty) return 0;
    final total = tasks.fold<double>(0, (sum, t) => sum + taskProgress(t));
    return (total / tasks.length).round();
  }

  int _categoryScore(TaskTag tag) {
    final categoryTasks = tasks.where((t) => t.tag == tag).toList();
    if (categoryTasks.isEmpty) return 0;
    final total =
        categoryTasks.fold<double>(0, (sum, t) => sum + taskProgress(t));
    return (total / categoryTasks.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, theme) {
        return Theme(
          data: AppTheme.company(theme),
          child: Scaffold(
            backgroundColor: theme.backgroundColor,
            appBar: AppBar(
              backgroundColor: theme.surfaceColor,
              foregroundColor: theme.inkColor,
              surfaceTintColor: Colors.transparent,
              title: Text(
                "$menteeName's goals",
                style: TextStyle(color: theme.inkColor),
              ),
            ),
            body: tasks.isEmpty
                ? Center(
                    child: Text(
                      'No goals yet.',
                      style: TextStyle(color: theme.mutedInkColor),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildScoreSummary(theme),
                      const SizedBox(height: 16),
                      ...tasks.map((task) => _buildTaskCard(theme, task)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildScoreSummary(CompanyThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.stars_rounded, color: theme.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_completedCount of ${tasks.length} goals completed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.inkColor,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'P ${_categoryScore(TaskTag.personal)}%  •  '
                  'Pro ${_categoryScore(TaskTag.professional)}%  •  '
                  'C ${_categoryScore(TaskTag.contribution)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.mutedInkColor,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$_score%',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: theme.inkColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(CompanyThemeData theme, Task task) {
    final progress = taskProgress(task).round();
    final isDone = taskIsEffectivelyCompleted(task);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isDone ? theme.primaryColor : theme.mutedInkColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.inkColor,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: task.tag.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        task.tag.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: task.tag.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$progress%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.inkColor,
                ),
              ),
            ],
          ),
          if (task.subTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(
                height: 1, color: theme.primaryColor.withValues(alpha: 0.12)),
            const SizedBox(height: 8),
            ...task.subTasks.map(
              (subTask) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      subTask.isCompleted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: subTask.isCompleted
                          ? theme.primaryColor
                          : theme.mutedInkColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subTask.title,
                        style: TextStyle(
                          color: theme.inkColor,
                          decoration: subTask.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
