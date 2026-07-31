import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/daily_score_service.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_membership_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/notifications/fasting_notification_service.dart';
import 'package:selfcare_projects/src/services/todo_task_api_service.dart';
import 'package:selfcare_projects/src/services/user_point_api_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodoList());
}

class TodoList extends StatelessWidget {
  const TodoList({super.key});

  @override
  Widget build(BuildContext context) {
    return const TodoListScreen();
  }
}

Color _onSurfaceFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

// Task model
enum TaskTag { personal, professional, contribution, none }

enum GoalType { longTerm, everyday }

const List<String> _defaultDailyTrackerTaskIds = [
  'call',
  'steps',
  'exercise',
  'meditation',
  'learning',
  'addValue',
];

extension TaskTagExtension on TaskTag {
  String get displayName {
    switch (this) {
      case TaskTag.personal:
        return 'Personal'; // Shortened from 'Personal Goals'
      case TaskTag.professional:
        return 'Professional'; // Shortened from 'Professional Milestones'
      case TaskTag.contribution:
        return 'Contribution'; // Shortened from 'Contribution Goals'
      case TaskTag.none:
        return 'No Tag';
    }
  }

  String get fullDisplayName {
    switch (this) {
      case TaskTag.personal:
        return 'Personal Goals';
      case TaskTag.professional:
        return 'Professional Milestones';
      case TaskTag.contribution:
        return 'Contribution Goals';
      case TaskTag.none:
        return 'No Tag';
    }
  }

  // tag colors
  Color get color {
    switch (this) {
      case TaskTag.personal:
        return const Color(0xFF6D849A);
      case TaskTag.professional:
        return const Color(0xFFCE8F5A);
      case TaskTag.contribution:
        return const Color(0xFF90A17D);
      case TaskTag.none:
        return Colors.grey;
    }
  }

  // background tag colors
  Color get lightColor {
    switch (this) {
      case TaskTag.personal:
        return Color(0xFF7AF1FF);
      case TaskTag.professional:
        return Color(0xFFFCE0AC);
      case TaskTag.contribution:
        return Color(0xFFBBD1A2);
      case TaskTag.none:
        return Color(0xFFF5F5F5);
    }
  }
}

extension GoalTypeExtension on GoalType {
  String get displayName {
    switch (this) {
      case GoalType.longTerm:
        return 'Long Term Goal';
      case GoalType.everyday:
        return 'Everyday Goal';
    }
  }

  String get storageValue {
    switch (this) {
      case GoalType.longTerm:
        return 'LONG_TERM';
      case GoalType.everyday:
        return 'EVERYDAY';
    }
  }
}

// create task
class TaskSubItem {
  String id;
  String title;
  bool isCompleted;
  DateTime createdAt;
  DateTime? updatedAt;

  TaskSubItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static DateTime? _dateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value;
    return null;
  }

  factory TaskSubItem.fromJson(Map<String, dynamic> json) => TaskSubItem(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        isCompleted: json['isCompleted'] == true,
        createdAt: _dateFromValue(json['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _dateFromValue(json['updatedAt']),
      );

  TaskSubItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskSubItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class Task {
  String id;
  String title;
  String description;
  bool isCompleted;
  GoalType goalType;
  DateTime startDate;
  DateTime dueDate;
  TaskTag tag;
  DateTime createdAt;
  DateTime? updatedAt;
  DateTime? completedAt;
  List<DateTime> completionDates;
  List<TaskSubItem> subTasks;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.goalType = GoalType.longTerm,
    required this.startDate,
    required this.dueDate,
    this.isCompleted = false,
    this.tag = TaskTag.none,
    DateTime? createdAt,
    this.updatedAt,
    this.completedAt,
    List<DateTime>? completionDates,
    List<TaskSubItem>? subTasks,
  })  : createdAt = createdAt ?? DateTime.now(),
        completionDates = completionDates ?? <DateTime>[],
        subTasks = subTasks ?? <TaskSubItem>[];

  // Convert to and from JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isCompleted': isCompleted,
        'goalType': goalType.storageValue,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'tag': tag.index,
        'tagIndex': tag.index,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'completionDates':
            completionDates.map((date) => date.toIso8601String()).toList(),
        'subTasks': subTasks.map((subTask) => subTask.toJson()).toList(),
      };

  static DateTime? _dateFromValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value;
    return null;
  }

  static TaskTag _tagFromValue(dynamic value) {
    if (value is num) {
      return TaskTag.values[value.toInt().clamp(0, TaskTag.values.length - 1)];
    }

    final raw = value?.toString().trim().toLowerCase() ?? '';
    if (raw.isEmpty) return TaskTag.none;
    final normalized = raw
        .replaceAll(RegExp(r'[\s_\-]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    switch (normalized) {
      case 'personal':
      case 'personalgoals':
        return TaskTag.personal;
      case 'professional':
      case 'professionalmilestones':
      case 'professionalgoals':
        return TaskTag.professional;
      case 'contribution':
      case 'contributiongoals':
        return TaskTag.contribution;
      case 'none':
      case 'notag':
        return TaskTag.none;
      default:
        final parsed = int.tryParse(raw);
        if (parsed != null) {
          return TaskTag
              .values[parsed.clamp(0, TaskTag.values.length - 1).toInt()];
        }

        if (normalized.contains('personal')) return TaskTag.personal;
        if (normalized.contains('professional')) {
          return TaskTag.professional;
        }
        if (normalized.contains('contribution')) {
          return TaskTag.contribution;
        }
        return TaskTag.none;
    }
  }

  static GoalType _goalTypeFromValue(dynamic value) {
    final raw = value?.toString().trim().toUpperCase() ?? '';
    final normalized = raw.replaceAll(RegExp(r'[\s_\-]+'), '');
    switch (normalized) {
      case 'EVERYDAY':
      case 'DAILY':
        return GoalType.everyday;
      case 'LONGTERM':
      case 'LONGTERMGOAL':
      case 'MILESTONE':
      case 'LONGTERMTASK':
      case 'LONGTERMGOALS':
        return GoalType.longTerm;
      default:
        return GoalType.longTerm;
    }
  }

  static List<DateTime> _dateListFromValue(dynamic value) {
    if (value is! List) return <DateTime>[];
    return value
        .whereType<Object>()
        .map((item) => DateTime.tryParse(item.toString()))
        .whereType<DateTime>()
        .map(DateUtils.dateOnly)
        .toList();
  }

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        isCompleted: json['isCompleted'] == true,
        goalType: _goalTypeFromValue(json['goalType']),
        startDate: DateTime.tryParse(
              (json['startDate'] ?? json['start_date'])?.toString() ?? '',
            ) ??
            DateTime.tryParse(json['dueDate']?.toString() ?? '') ??
            DateTime.now(),
        dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? '') ??
            DateTime.now(),
        tag: _tagFromValue(json['tag'] ?? json['tagIndex']),
        createdAt: _dateFromValue(json['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: _dateFromValue(json['updatedAt']),
        completedAt: _dateFromValue(json['completedAt']),
        completionDates: _dateListFromValue(
          json['completionDates'] ?? json['completion_dates'],
        ),
        subTasks: (json['subTasks'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((subTask) =>
                TaskSubItem.fromJson(Map<String, dynamic>.from(subTask)))
            .toList(),
      );
}

double taskProgress(Task task) {
  if (task.goalType == GoalType.everyday) {
    final rangeStart = DateUtils.dateOnly(task.startDate);
    final rangeEnd = DateUtils.dateOnly(task.dueDate);

    if (rangeEnd.isBefore(rangeStart)) return 0;

    final eligibleDays = rangeEnd.difference(rangeStart).inDays + 1;
    if (eligibleDays <= 0) return 0;

    final completedDays = task.completionDates
        .map(DateUtils.dateOnly)
        .where((day) => !day.isBefore(rangeStart) && !day.isAfter(rangeEnd))
        .toSet()
        .length;

    return (completedDays / eligibleDays) * 100;
  }

  if (task.subTasks.isNotEmpty) {
    final total = task.subTasks.length;
    if (total == 0) return task.isCompleted ? 100 : 0;
    final completed =
        task.subTasks.where((subTask) => subTask.isCompleted).length;
    return (completed / total) * 100;
  }

  return task.isCompleted ? 100 : 0;
}

bool taskIsEffectivelyCompleted(Task task) {
  if (task.goalType == GoalType.everyday) {
    final today = DateUtils.dateOnly(DateTime.now());
    final dueDate = DateUtils.dateOnly(task.dueDate);
    return !today.isBefore(dueDate) && taskProgress(task) >= 100;
  }

  return taskProgress(task) >= 100;
}

double taskScoreProgress(Task task) {
  if (task.goalType == GoalType.everyday) {
    return taskProgress(task);
  }

  if (!taskIsEffectivelyCompleted(task)) return 0;

  final completedAt = DateUtils.dateOnly(task.completedAt ?? DateTime.now());
  final dueDate = DateUtils.dateOnly(task.dueDate);

  return completedAt.isAfter(dueDate) ? 0 : 100;
}

bool taskOccursOnDate(Task task, DateTime day) {
  final selectedDay = DateUtils.dateOnly(day);
  final startDate = DateUtils.dateOnly(task.startDate);
  final dueDate = DateUtils.dateOnly(task.dueDate);
  final rangeStart = startDate.isAfter(dueDate) ? dueDate : startDate;
  final rangeEnd = dueDate.isBefore(startDate) ? startDate : dueDate;

  return !selectedDay.isBefore(rangeStart) && !selectedDay.isAfter(rangeEnd);
}

List<DateTime> taskCalendarDays(Task task) {
  final startDate = DateUtils.dateOnly(task.startDate);
  final dueDate = DateUtils.dateOnly(task.dueDate);
  final rangeStart = startDate.isAfter(dueDate) ? dueDate : startDate;
  final rangeEnd = dueDate.isBefore(startDate) ? startDate : dueDate;
  final days = <DateTime>[];

  for (var day = rangeStart;
      !day.isAfter(rangeEnd);
      day = day.add(const Duration(days: 1))) {
    days.add(DateUtils.dateOnly(day));
  }

  return days;
}

bool taskHasCompletionOnDate(Task task, DateTime day) {
  final selectedDay = DateUtils.dateOnly(day);
  return task.completionDates
      .map(DateUtils.dateOnly)
      .any((completedDay) => completedDay == selectedDay);
}

bool taskCalendarDayIsEnabled(Task task, DateTime day, {DateTime? today}) {
  final selectedDay = DateUtils.dateOnly(day);
  final currentDay = DateUtils.dateOnly(today ?? DateTime.now());
  return taskOccursOnDate(task, selectedDay) &&
      !selectedDay.isAfter(currentDay);
}

Task syncTaskCompletion(Task task, {DateTime? completedAt}) {
  final progress = taskProgress(task);
  final isCompleted = progress >= 100;
  task.isCompleted = isCompleted;

  if (isCompleted) {
    task.completedAt ??= completedAt ?? DateTime.now();
  } else {
    task.completedAt = null;
  }

  return task;
}

class FirestoreRepository {
  final TodoTaskApiService _api = TodoTaskApiService.instance;

  String? get userId => AuthService.instance.currentSession?.id.toString();

  Future<List<Task>> loadTasks() async {
    if (userId == null) {
      print('No user ID found. User not logged in?');
      return [];
    }

    print('Fetching tasks for user: $userId');

    try {
      final tasks = await _api.fetchTasks();
      if (tasks.isEmpty) {
        print('No tasks found for user $userId');
      }
      return tasks.map(Task.fromJson).toList();
    } catch (e) {
      print('Error loading tasks: $e');
      return [];
    }
  }

  Future<void> addTask(Task task) async {
    try {
      print('Adding task for user: $userId');
      final taskData = await _api.saveTask({
        'id': task.id.isEmpty ? null : task.id,
        'title': task.title,
        'description': task.description,
        'goal_type': task.goalType.storageValue,
        'start_date': task.startDate.toIso8601String(),
        'due_date': task.dueDate.toIso8601String(),
        'tag': task.tag.name,
        'tag_index': task.tag.index,
        'is_completed': task.isCompleted,
        'completed_at': task.completedAt?.toIso8601String(),
        'completion_dates':
            task.completionDates.map((date) => date.toIso8601String()).toList(),
        'sub_tasks': task.subTasks.map((subTask) => subTask.toJson()).toList(),
      });
      task.id = (taskData['id'] as String?) ?? task.id;
      print('Task added successfully with ID: ${task.id}');
    } catch (e) {
      print('Error adding task: $e');
    }
  }

  Future<void> updateTask(Task task) async {
    try {
      await _api.updateTask(task.id, {
        'title': task.title,
        'description': task.description,
        'goal_type': task.goalType.storageValue,
        'start_date': task.startDate.toIso8601String(),
        'due_date': task.dueDate.toIso8601String(),
        'tag': task.tag.name,
        'tag_index': task.tag.index,
        'is_completed': task.isCompleted,
        'completed_at': task.completedAt?.toIso8601String(),
        'completion_dates':
            task.completionDates.map((date) => date.toIso8601String()).toList(),
        'sub_tasks': task.subTasks.map((subTask) => subTask.toJson()).toList(),
      });
    } catch (e) {
      print('Error updating task: $e');
    }
  }

  Future<void> deleteTask(String id) async {
    try {
      await _api.deleteTask(id);
      print('Task deleted successfully: $id');
    } catch (e) {
      print('Error deleting task: $e');
    }
  }

  Future<void> migrateFromLocalStorage() async {
    try {
      final localTasks = await TodoRepository.loadTasks();

      for (final task in localTasks) {
        await addTask(task);
      }

      print('Migration completed successfully!');
    } catch (e) {
      print('Error during migration: $e');
    }
  }
}

// Keep the original TodoRepository for migration purposes
class TodoRepository {
  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/todos.json');
  }

  static Future<List<Task>> loadTasks() async {
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        return [];
      }

      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => Task.fromJson(json)).toList();
    } catch (e) {
      print('Error loading tasks: $e');
      return [];
    }
  }

  static Future<void> saveTasks(List<Task> tasks) async {
    try {
      final file = await _localFile;
      final jsonList = tasks.map((task) => task.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Error saving tasks: $e');
    }
  }
}

// Main screen
class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  static const List<TaskTag> _goalCategories = [
    TaskTag.personal,
    TaskTag.professional,
    TaskTag.contribution,
  ];

  List<Task> _tasks = [];
  bool _isLoading = true;
  bool _useAbundanceGoalsHub = false;
  bool _isResolvingCompanyMode = true;
  int _currentTabIndex = 0;
  TaskTag? _selectedGoalCategory;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Create an instance of FirestoreRepository with fallback
  late final FirestoreRepository _repository;

  CompanyThemeData _currentCompanyTheme() {
    final userId = AuthService.instance.currentSession?.id.toString() ?? '';
    return CompanyThemeService.cachedThemeForUser(userId) ??
        CompanyThemeData.standard;
  }

  // Constructor with repository initialization
  _TodoListScreenState() {
    try {
      _repository = FirestoreRepository();
      print('Firestore repository initialized');
    } catch (e) {
      print('Error initializing Firestore repository: $e');
      // This catch block allows the app to continue even if Firestore initialization fails
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveCompanyMode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _resolveCompanyMode() async {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _useAbundanceGoalsHub = false;
        _isResolvingCompanyMode = false;
      });
      await _loadTasks();
      return;
    }

    try {
      final membershipData =
          await CompanyMembershipService.loadForUser(session.id.toString());
      final useGoalsHub =
          _isAbundanceCompany(membershipData.activeMembership);

      if (!mounted) return;
      setState(() {
        _useAbundanceGoalsHub = useGoalsHub;
        _isResolvingCompanyMode = false;
        _isLoading = !useGoalsHub;
      });

      if (!useGoalsHub) {
        await _loadTasks();
      }
    } catch (error) {
      debugPrint('Failed to resolve todo list company mode: $error');
      if (!mounted) return;
      setState(() {
        _useAbundanceGoalsHub = false;
        _isResolvingCompanyMode = false;
      });
      await _loadTasks();
    }
  }

  bool _isAbundanceCompany(CompanyMembership? membership) {
    return AbundanceCompany.matches(membership?.code, membership?.name);
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
    });

    // Load tasks from Firestore instead of local storage
    final tasks = await _repository.loadTasks();
    for (final task in tasks) {
      syncTaskCompletion(task, completedAt: task.completedAt);
    }

    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });

    await _syncTaskNotifications(tasks);
    await _syncTodoListScore();
  }

  void _addTask(Task task) async {
    try {
      if (task.id.isEmpty) {
        task.id = DateTime.now().millisecondsSinceEpoch.toString();
      }
      task.createdAt = DateTime.now();
      syncTaskCompletion(task, completedAt: task.completedAt);

      // Add to Firestore first
      await _repository.addTask(task);
      await _scheduleTaskNotification(task);

      // Then reload tasks to ensure UI is in sync with database
      await _loadTasks();
    } catch (e) {
      print('Error adding task: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add goal. Please try again.')),
      );
    }
  }

  void _deleteTask(String id) async {
    // First remove from UI for immediate feedback
    setState(() {
      _tasks.removeWhere((task) => task.id == id);
    });

    try {
      // Then delete from Firestore
      await _repository.deleteTask(id);
      await _cancelTaskNotification(id);
      await _syncTodoListScore();
      print('Task deleted successfully with ID: $id');
    } catch (e) {
      print('Error deleting task: $e');
      // If deletion fails, reload tasks to ensure UI is in sync with database
      await _loadTasks();
    }
  }

  void _toggleTaskCompletion(String id) async {
    try {
      // Find the task in the local list
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index != -1) {
        // Create a local copy of the task
        final task = _tasks[index];
        if (task.goalType == GoalType.everyday) {
          _toggleTaskCompletionDate(task.id, DateTime.now());
          return;
        }
        final shouldComplete = !taskIsEffectivelyCompleted(task);
        if (task.subTasks.isNotEmpty) {
          for (final subTask in task.subTasks) {
            subTask.isCompleted = shouldComplete;
            subTask.updatedAt = DateTime.now();
          }
        } else {
          task.isCompleted = shouldComplete;
        }
        task.updatedAt = DateTime.now();
        syncTaskCompletion(
          task,
          completedAt: shouldComplete ? DateTime.now() : null,
        );

        // Update the task in Firestore
        await _repository.updateTask(task);
        if (task.isCompleted) {
          await _cancelTaskNotification(task.id);
        } else {
          await _scheduleTaskNotification(task);
        }

        // Update the UI immediately for better user experience
        setState(() {
          _tasks[index] = task;
        });

        await _syncTodoListScore();

        print('Task completion toggled: $id, New status: ${task.isCompleted}');
      } else {
        print('Task not found with ID: $id');
      }
    } catch (e) {
      print('Error toggling task completion: $e');
      // If the update fails, reload all tasks to ensure UI is in sync
      await _loadTasks();
    }
  }

  void _toggleTaskCompletionDate(String id, DateTime selectedDay) async {
    try {
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index == -1) {
        print('Task not found with ID: $id');
        return;
      }

      final task = _tasks[index];
      final normalizedSelectedDay = DateUtils.dateOnly(selectedDay);
      final completionKeys = task.completionDates
          .map(DateUtils.dateOnly)
          .map((date) => DateFormat('yyyy-MM-dd').format(date))
          .toSet();
      final selectedKey =
          DateFormat('yyyy-MM-dd').format(normalizedSelectedDay);

      if (completionKeys.contains(selectedKey)) {
        completionKeys.remove(selectedKey);
      } else {
        completionKeys.add(selectedKey);
      }

      task.completionDates = completionKeys
          .map((date) => DateTime.parse(date))
          .toList()
        ..sort((a, b) => a.compareTo(b));
      task.updatedAt = DateTime.now();
      syncTaskCompletion(task, completedAt: normalizedSelectedDay);

      await _repository.updateTask(task);
      if (task.isCompleted) {
        await _cancelTaskNotification(task.id);
      } else {
        await _scheduleTaskNotification(task);
      }

      setState(() {
        _tasks[index] = task;
      });

      await _syncTodoListScore();
    } catch (e) {
      print('Error toggling task completion date: $e');
      await _loadTasks();
    }
  }

  void _toggleSubTaskCompletion(
    String taskId,
    String subTaskId,
    bool? value,
  ) async {
    try {
      final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
      if (taskIndex == -1) {
        print('Task not found with ID: $taskId');
        return;
      }

      final task = _tasks[taskIndex];
      final subTaskIndex =
          task.subTasks.indexWhere((subTask) => subTask.id == subTaskId);
      if (subTaskIndex == -1) {
        print('Subtask not found with ID: $subTaskId');
        return;
      }

      task.subTasks[subTaskIndex].isCompleted = value ?? false;
      task.subTasks[subTaskIndex].updatedAt = DateTime.now();
      task.updatedAt = DateTime.now();
      syncTaskCompletion(
        task,
        completedAt: task.completedAt,
      );

      await _repository.updateTask(task);
      if (task.isCompleted) {
        await _cancelTaskNotification(task.id);
      } else {
        await _scheduleTaskNotification(task);
      }

      setState(() {
        _tasks[taskIndex] = task;
      });

      await _syncTodoListScore();
    } catch (e) {
      print('Error toggling subtask completion: $e');
      await _loadTasks();
    }
  }

  Future<void> _syncTaskNotifications(List<Task> tasks) async {
    await FastingNotificationService.instance.ensurePermissions();
    for (final task in tasks) {
      if (taskIsEffectivelyCompleted(task)) {
        await _cancelTaskNotification(task.id);
      } else {
        await _scheduleTaskNotification(task);
      }
    }
  }

  Future<void> _scheduleTaskNotification(Task task) async {
    if (taskIsEffectivelyCompleted(task)) {
      await _cancelTaskNotification(task.id);
      return;
    }

    await FastingNotificationService.instance.ensurePermissions();
    await FastingNotificationService.instance.scheduleTodoDueNotification(
      taskId: task.id,
      title: task.title,
      dueDate: task.dueDate,
    );
  }

  Future<void> _cancelTaskNotification(String taskId) async {
    await FastingNotificationService.instance.cancelTodoDueNotification(taskId);
  }

  TaskSubItem _createSubTask(String title) {
    return TaskSubItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
    );
  }

  Widget _buildTaskProgressBar({
    required Task task,
    required Color accentColor,
    required Color mutedColor,
    required bool isCompleted,
  }) {
    final progress = taskProgress(task).clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress / 100,
                  backgroundColor: mutedColor.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCompleted
                        ? accentColor
                        : accentColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${progress.round()}%',
              style: TextStyle(
                fontSize: 12,
                color: mutedColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (task.subTasks.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${task.subTasks.where((subTask) => subTask.isCompleted).length}/${task.subTasks.length} subtasks complete',
            style: TextStyle(
              fontSize: 12,
              color: mutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubtaskRows({
    required Task task,
    required Color titleColor,
    required Color mutedColor,
    required Color accentColor,
  }) {
    if (task.subTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subtasks',
            style: TextStyle(
              fontSize: 12,
              color: mutedColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final subTask in task.subTasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Checkbox(
                      value: subTask.isCompleted,
                      onChanged: (value) {
                        _toggleSubTaskCompletion(task.id, subTask.id, value);
                      },
                      shape: const CircleBorder(),
                      checkColor: Colors.white,
                      activeColor: accentColor,
                      side:
                          BorderSide(color: mutedColor.withValues(alpha: 0.8)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        subTask.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: subTask.isCompleted ? mutedColor : titleColor,
                          decoration: subTask.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          fontWeight: FontWeight.w600,
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

  Widget _buildTaskDateStrip({
    required Task task,
    required CompanyThemeData companyTheme,
    VoidCallback? onDayChanged,
  }) {
    final days = taskCalendarDays(task);
    if (days.isEmpty) return const SizedBox.shrink();

    final today = DateUtils.dateOnly(DateTime.now());
    final borderColor = companyTheme.isDark
        ? companyTheme.iconColor.withValues(alpha: 0.24)
        : companyTheme.mutedInkColor.withValues(alpha: 0.18);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Check day',
            style: TextStyle(
              fontSize: 12,
              color: companyTheme.mutedInkColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: days.map((day) {
                final isEnabled = taskCalendarDayIsEnabled(
                  task,
                  day,
                  today: today,
                );
                final isSelected = taskHasCompletionOnDate(task, day);
                final isFuture = day.isAfter(today);
                final backgroundColor = isSelected
                    ? companyTheme.primaryColor.withValues(alpha: 0.12)
                    : companyTheme.surfaceColor;
                final cellBorderColor = isSelected
                    ? companyTheme.primaryColor
                    : isFuture
                        ? borderColor.withValues(alpha: 0.4)
                        : borderColor;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: isEnabled
                        ? () {
                            _toggleTaskCompletionDate(task.id, day);
                            onDayChanged?.call();
                          }
                        : null,
                    child: Container(
                      width: 56,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cellBorderColor),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('EEE').format(day),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isFuture
                                  ? companyTheme.mutedInkColor.withValues(
                                      alpha: 0.55,
                                    )
                                  : companyTheme.inkColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isFuture
                                  ? companyTheme.mutedInkColor.withValues(
                                      alpha: 0.55,
                                    )
                                  : companyTheme.inkColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : isFuture
                                    ? Icons.lock_outline
                                    : Icons.circle_outlined,
                            size: 15,
                            color: isSelected
                                ? companyTheme.primaryColor
                                : isFuture
                                    ? companyTheme.mutedInkColor.withValues(
                                        alpha: 0.5,
                                      )
                                    : companyTheme.mutedInkColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCalendarPanel({
    required Task task,
    required CompanyThemeData companyTheme,
    required DateTime visibleMonth,
    required VoidCallback onDayChanged,
    required VoidCallback onPreviousMonth,
    required VoidCallback onNextMonth,
  }) {
    final months = _taskCalendarMonthStarts(task);
    if (months.isEmpty) return const SizedBox.shrink();
    final selectedMonth = months.firstWhere(
      (month) =>
          month.year == visibleMonth.year && month.month == visibleMonth.month,
      orElse: () => months.first,
    );
    final monthIndex = months.indexWhere(
      (month) =>
          month.year == selectedMonth.year &&
          month.month == selectedMonth.month,
    );
    final canGoPrevious = monthIndex > 0;
    final canGoNext = monthIndex < months.length - 1;

    final borderColor = companyTheme.isDark
        ? companyTheme.iconColor.withValues(alpha: 0.24)
        : companyTheme.mutedInkColor.withValues(alpha: 0.18);
    final completedDays = taskCalendarCompletedDays(task);
    final totalDays = taskCalendarTotalDays(task);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: companyTheme.surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: companyTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                'Calendar',
                style: TextStyle(
                  fontSize: 13,
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: canGoPrevious ? onPreviousMonth : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: companyTheme.inkColor,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Previous month',
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(selectedMonth),
                    style: TextStyle(
                      fontSize: 13,
                      color: companyTheme.inkColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    onPressed: canGoNext ? onNextMonth : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: companyTheme.inkColor,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Next month',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$completedDays/$totalDays days done',
            style: TextStyle(
              fontSize: 11,
              color: companyTheme.mutedInkColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap a day to mark it done',
            style: TextStyle(
              fontSize: 11,
              color: companyTheme.mutedInkColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildTaskCalendarMonthSection(
            task: task,
            companyTheme: companyTheme,
            monthStart: selectedMonth,
            onDayChanged: onDayChanged,
          ),
        ],
      ),
    );
  }

  List<DateTime> _taskCalendarMonthStarts(Task task) {
    final rangeStart = DateUtils.dateOnly(task.startDate);
    final rangeEnd = DateUtils.dateOnly(task.dueDate);
    final firstMonth = DateTime(rangeStart.year, rangeStart.month);
    final lastMonth = DateTime(rangeEnd.year, rangeEnd.month);
    final months = <DateTime>[];

    for (var month = firstMonth;
        !month.isAfter(lastMonth);
        month = DateTime(month.year, month.month + 1)) {
      months.add(DateTime(month.year, month.month));
    }

    return months;
  }

  int taskCalendarCompletedDays(Task task) {
    final rangeStart = DateUtils.dateOnly(task.startDate);
    final rangeEnd = DateUtils.dateOnly(task.dueDate);
    return task.completionDates
        .map(DateUtils.dateOnly)
        .where((day) => !day.isBefore(rangeStart) && !day.isAfter(rangeEnd))
        .toSet()
        .length;
  }

  int taskCalendarTotalDays(Task task) => taskCalendarDays(task).length;

  Widget _buildTaskCalendarMonthSection({
    required Task task,
    required CompanyThemeData companyTheme,
    required DateTime monthStart,
    required VoidCallback onDayChanged,
  }) {
    final rangeStart = DateUtils.dateOnly(task.startDate);
    final rangeEnd = DateUtils.dateOnly(task.dueDate);
    final today = DateUtils.dateOnly(DateTime.now());
    final firstOfMonth = DateTime(monthStart.year, monthStart.month);
    final daysInMonth =
        DateUtils.getDaysInMonth(monthStart.year, monthStart.month);
    final leadingEmptyCells = firstOfMonth.weekday % 7;
    final totalCells = leadingEmptyCells + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final borderColor = companyTheme.isDark
        ? companyTheme.iconColor.withValues(alpha: 0.24)
        : companyTheme.mutedInkColor.withValues(alpha: 0.18);

    Widget buildDayCell(DateTime day) {
      final isSelected = taskHasCompletionOnDate(task, day);
      final isEnabled = taskCalendarDayIsEnabled(task, day, today: today);
      final isFuture = day.isAfter(today);
      final isOutsideRange = day.isBefore(rangeStart) || day.isAfter(rangeEnd);
      final backgroundColor = isSelected
          ? companyTheme.primaryColor.withValues(alpha: 0.12)
          : companyTheme.surfaceColor;
      final cellBorderColor = isSelected
          ? companyTheme.primaryColor
          : isFuture || isOutsideRange
              ? borderColor.withValues(alpha: 0.4)
              : borderColor;
      final textColor = isFuture || isOutsideRange
          ? companyTheme.mutedInkColor.withValues(alpha: 0.55)
          : companyTheme.inkColor;
      final iconColor = isSelected
          ? companyTheme.primaryColor
          : isFuture || isOutsideRange
              ? companyTheme.mutedInkColor.withValues(alpha: 0.5)
              : companyTheme.mutedInkColor;

      return GestureDetector(
        onTap: isEnabled
            ? () {
                _toggleTaskCompletionDate(task.id, day);
                onDayChanged();
              }
            : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cellBorderColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                isSelected
                    ? Icons.check_circle
                    : isFuture
                        ? Icons.lock_outline
                        : Icons.circle_outlined,
                size: 14,
                color: iconColor,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: companyTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(monthStart),
            style: TextStyle(
              fontSize: 14,
              color: companyTheme.inkColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: Center(child: Text('S'))),
              Expanded(child: Center(child: Text('M'))),
              Expanded(child: Center(child: Text('T'))),
              Expanded(child: Center(child: Text('W'))),
              Expanded(child: Center(child: Text('T'))),
              Expanded(child: Center(child: Text('F'))),
              Expanded(child: Center(child: Text('S'))),
            ],
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < rows; row++) ...[
            Row(
              children: List.generate(7, (column) {
                final cellIndex = row * 7 + column;
                final dayNumber = cellIndex - leadingEmptyCells + 1;
                if (cellIndex < leadingEmptyCells ||
                    dayNumber < 1 ||
                    dayNumber > daysInMonth) {
                  return const Expanded(
                      child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: SizedBox(height: 48),
                  ));
                }

                final day =
                    DateTime(monthStart.year, monthStart.month, dayNumber);
                return Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: buildDayCell(day),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubtaskEditor({
    required List<TaskSubItem> subTasks,
    required TextEditingController controller,
    required void Function(VoidCallback fn) setDialogState,
    required CompanyThemeData companyTheme,
  }) {
    final surfaceColor = companyTheme.surfaceColor;
    final textColor = companyTheme.inkColor;
    final mutedColor = companyTheme.mutedInkColor;
    final borderColor = companyTheme.isDark
        ? companyTheme.primaryColor.withValues(alpha: 0.22)
        : mutedColor.withValues(alpha: 0.22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Add subtask',
                  hintText: 'Example: Drink water',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: companyTheme.iconColor,
                      width: 1.4,
                    ),
                  ),
                  labelStyle: TextStyle(color: mutedColor),
                  hintStyle: TextStyle(color: mutedColor),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 12,
                  ),
                ),
                style: TextStyle(color: textColor),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                setDialogState(() {
                  subTasks.add(_createSubTask(value));
                  controller.clear();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: companyTheme.primaryColor,
                foregroundColor: _onSurfaceFor(companyTheme.primaryColor),
                elevation: 0,
              ),
              child: const Text('ADD'),
            ),
          ],
        ),
        if (subTasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < subTasks.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == subTasks.length - 1 ? 0 : 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: subTasks[index].isCompleted,
                          onChanged: (value) {
                            setDialogState(() {
                              subTasks[index].isCompleted = value ?? false;
                              subTasks[index].updatedAt = DateTime.now();
                            });
                          },
                          shape: const CircleBorder(),
                          checkColor: _onSurfaceFor(companyTheme.primaryColor),
                          activeColor: companyTheme.primaryColor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 13),
                            child: Text(
                              subTasks[index].title,
                              style: TextStyle(
                                fontSize: 14,
                                color: subTasks[index].isCompleted
                                    ? mutedColor
                                    : textColor,
                                decoration: subTasks[index].isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setDialogState(() {
                              subTasks.removeAt(index);
                            });
                          },
                          icon: const Icon(Icons.close),
                          color: mutedColor,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  int _totalGoalsForCategory(TaskTag category) {
    return _tasks.where((task) => task.tag == category).length;
  }

  int _completedGoalsForCategory(TaskTag category) {
    return _tasks
        .where((task) => task.tag == category && taskScoreProgress(task) >= 100)
        .length;
  }

  double _taskValueForCategory(TaskTag category) {
    final total = _totalGoalsForCategory(category);
    if (total == 0) return 0;
    return 100 / total;
  }

  int _categoryScore(TaskTag category) {
    final categoryTasks = _tasks.where((task) => task.tag == category).toList();
    final total = categoryTasks.length;
    if (total == 0) return 0;
    final totalProgress = categoryTasks.fold<double>(
      0,
      (runningTotal, task) => runningTotal + taskScoreProgress(task),
    );
    return (totalProgress / total).round();
  }

  int get _completedGoalCount =>
      _tasks.where((task) => taskScoreProgress(task) >= 100).length;

  int get _totalGoalCount => _tasks.length;

  int get _todoScore {
    if (_tasks.isEmpty) return 0;

    final totalProgress = _tasks.fold<double>(
      0,
      (runningTotal, task) => runningTotal + taskScoreProgress(task),
    );

    return (totalProgress / _tasks.length).round();
  }

  List<String> _dailyTrackerIdsFromUserData(Map<String, dynamic>? userData) {
    final rawItems = userData?['dailyTrackerItems'];
    if (rawItems is! List) return List.of(_defaultDailyTrackerTaskIds);

    final ids = rawItems
        .whereType<Map>()
        .map((item) => item['id'])
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != 'todoList')
        .toList();

    return ids.isEmpty ? List.of(_defaultDailyTrackerTaskIds) : ids;
  }

  bool _readDailyTrackerCompletion(
    Map<String, dynamic> tracker,
    String taskId,
  ) {
    final customDailyTasks = tracker['customDailyTasks'];
    if (customDailyTasks is Map) {
      final customTask = customDailyTasks[taskId];
      if (customTask is Map) return customTask['completed'] == true;
      if (customTask is bool) return customTask;
    }

    return tracker[taskId] == true;
  }

  Map<String, dynamic> _dailyTrackerScoreFields({
    required List<String> dailyTrackerIds,
    required Map<String, dynamic> tracker,
    required int todoListScore,
    required num todoListScoreContribution,
    required bool includeTodoListScore,
  }) {
    final clampedTodoListContribution = includeTodoListScore
        ? todoListScoreContribution.clamp(0, 100).toInt()
        : 0;
    final scoreSummary = DailyScoreService.summarizeTracker(
      {
        ...tracker,
        'todoListScore': todoListScore,
        'todoListScoreDailyContribution': clampedTodoListContribution,
        'todoListIncludedInTotal': includeTodoListScore,
      },
      dailyTrackerIds: dailyTrackerIds,
    );
    if (dailyTrackerIds.isEmpty) {
      return {
        'dailyTrackerScore': scoreSummary.dailyTrackerScore,
        'userTotalScore': scoreSummary.totalPoints.round(),
        'dailyTrackerCompletedCount': 0,
        'dailyTrackerCompletedWeight': 0,
        'dailyTrackerTaskCount': 0,
        'dailyTrackerTaskValue': 0,
        'todoListScoreDailyContribution': clampedTodoListContribution,
        'todoListIncludedInTotal': includeTodoListScore,
      };
    }

    final taskValue = 100 / dailyTrackerIds.length;
    double completedWeight = 0;
    int completedCount = 0;

    for (final taskId in dailyTrackerIds) {
      final progress = _readDailyTrackerCompletion(tracker, taskId) ? 1.0 : 0.0;

      completedWeight += progress;
      if (progress >= 1) completedCount += 1;
    }

    final dailyTrackerScore = scoreSummary.dailyTrackerScore;
    final userTotalScore = scoreSummary.totalPoints.round();

    return {
      'dailyTrackerScore': dailyTrackerScore,
      'userTotalScore': userTotalScore,
      'dailyTrackerCompletedCount': completedCount,
      'dailyTrackerCompletedWeight': completedWeight,
      'dailyTrackerTaskCount': dailyTrackerIds.length,
      'dailyTrackerTaskValue': taskValue,
      'todoListScoreDailyContribution': clampedTodoListContribution,
      'todoListIncludedInTotal': includeTodoListScore,
    };
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _syncTodoListScore() async {
    final session = AuthService.instance.currentSession;
    if (session == null) return;
    final userId = session.id.toString();

    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final completedCount = _completedGoalCount;
    final score = _todoScore;
    final membershipData = await CompanyMembershipService.loadForUser(userId);
    final previousDate = DateFormat('yyyy-MM-dd').format(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final previousTrackerResponse =
        await DailyTrackerApiService.instance.fetch(date: previousDate);
    final previousTracker = previousTrackerResponse['tracker'];
    final previousTrackerData = previousTracker is Map<String, dynamic>
        ? previousTracker
        : <String, dynamic>{};
    final previousTodoListScore =
        _readInt(previousTrackerData['todoListScore']).clamp(0, 100);
    final todoListScoreContribution =
        (score - previousTodoListScore).clamp(0, 100).toInt();
    final includeTodoListScore = score > 0;

    String? trackerUsername;
    Map<String, dynamic>? userData;
    try {
      userData = await UserService.getUserData();
      final dynamic rawUsername = userData['username'];
      trackerUsername = rawUsername is String ? rawUsername.trim() : null;
    } catch (error) {
      debugPrint('Failed to resolve todo tracker username: $error');
    }

    final trackerResponse =
        await DailyTrackerApiService.instance.fetch(date: todayDate);
    final trackerData = trackerResponse['tracker'];
    final trackerMap =
        trackerData is Map<String, dynamic> ? trackerData : <String, dynamic>{};
    final dailyTrackerIds = _dailyTrackerIdsFromUserData(userData);
    final dailyTrackerScoreFields = _dailyTrackerScoreFields(
      dailyTrackerIds: dailyTrackerIds,
      tracker: trackerMap,
      todoListScore: score,
      todoListScoreContribution: todoListScoreContribution,
      includeTodoListScore: includeTodoListScore,
    );

    await DailyTrackerApiService.instance.upsert(
      date: todayDate,
      todoList: completedCount > 0,
      todoListCount: completedCount,
      dailyTrackerScore: dailyTrackerScoreFields['dailyTrackerScore'] as int?,
      todoListScore: score,
      todoListScoreDailyContribution: todoListScoreContribution,
      todoListIncludedInTotal: includeTodoListScore,
      userTotalScore:
          (dailyTrackerScoreFields['userTotalScore'] as num?)?.round(),
      username: trackerUsername,
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
      customDailyTasks: trackerMap['customDailyTasks'] is Map<String, dynamic>
          ? trackerMap['customDailyTasks'] as Map<String, dynamic>
          : null,
    );

    await _syncUserPoints(
      userId: userId,
      userEmail: session.email,
      userName: session.name,
      username: trackerUsername,
      userData: userData ?? <String, dynamic>{},
      trackerData: {
        ...trackerMap,
        ...dailyTrackerScoreFields,
        'todoListScore': score,
        'todoListScoreDailyContribution': todoListScoreContribution,
        'todoListIncludedInTotal': includeTodoListScore,
      },
    );
  }

  Future<void> _syncUserPoints({
    required String userId,
    required String userEmail,
    required String userName,
    required String? username,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> trackerData,
  }) async {
    final resolvedUsername = username?.trim().isNotEmpty == true
        ? username!.trim()
        : (userEmail.trim().isNotEmpty
            ? userEmail.split('@').first
            : userName.trim().isNotEmpty
                ? userName.trim()
                : 'User');
    final dailyTrackerScore =
        _readInt(trackerData['dailyTrackerScore']).clamp(0, 100).toInt();
    final todoListScore =
        _readInt(trackerData['todoListScore']).clamp(0, 100).toInt();
    final todoListContribution =
        _readInt(trackerData['todoListScoreDailyContribution'])
            .clamp(0, 100)
            .toInt();
    final includeTodoListScore = trackerData['todoListIncludedInTotal'] == true;
    final effectiveTodoListScore =
        todoListScore > 0 ? todoListScore : todoListContribution;
    final totalPoints = includeTodoListScore
        ? ((dailyTrackerScore + effectiveTodoListScore) / 2).clamp(0, 100)
        : dailyTrackerScore;
    final totalPointsInt = totalPoints.round();
    final membershipData = CompanyMembershipService.fromUserData(userData);

    await UserPointApiService.instance.upsert(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      username: resolvedUsername,
      totalPoints: totalPoints,
      dailyTrackerScore: dailyTrackerScore,
      todoListScore: todoListScore,
      todoListScoreDailyContribution: todoListContribution,
      todoListIncludedInTotal: includeTodoListScore,
      userTotalScore: totalPointsInt,
      server: userData['team']?.toString() ?? 'Default',
      companyId: membershipData.activeMembership?.id,
      companyCode: membershipData.activeMembership?.code,
      companyName: membershipData.activeMembership?.name,
      activityCounts: {
        'dailyTrackerScore': dailyTrackerScore,
        'todoListScore': todoListScore,
        'todoListScoreDailyContribution': todoListContribution,
        'todoListIncludedInTotal': includeTodoListScore,
        'userTotalScore': totalPoints,
      },
    );
  }

  // Show migration dialog - useful for first-time setup
  void _showMigrationDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Migrate Data'),
        content: const Text(
            'Would you like to migrate your existing tasks to Firebase Firestore?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Show loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              // Perform migration
              await _repository.migrateFromLocalStorage();
              if (!mounted) return;

              // Dismiss loading indicator
              Navigator.pop(context);

              // Reload tasks
              _loadTasks();

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Migration completed!')),
              );
            },
            child: const Text('MIGRATE'),
          ),
        ],
      ),
    );
  }

  List<Task> _getFilteredTasks() {
    final List<Task> filteredTasks;
    final normalizedQuery = _searchQuery.trim().toLowerCase();

    // First filter by search query
    final searchFiltered = normalizedQuery.isEmpty
        ? _tasks
        : _tasks.where((task) {
            return task.title.toLowerCase().contains(normalizedQuery) ||
                task.description.toLowerCase().contains(normalizedQuery) ||
                task.tag.displayName.toLowerCase().contains(normalizedQuery);
          }).toList();

    final categoryFiltered = _selectedGoalCategory == null
        ? searchFiltered
        : searchFiltered
            .where((task) => task.tag == _selectedGoalCategory)
            .toList();

    // Then filter by completion tab
    switch (_currentTabIndex) {
      case 0: // All
        filteredTasks = categoryFiltered;
        break;
      case 1: // Pending
        filteredTasks = categoryFiltered
            .where((task) => !taskIsEffectivelyCompleted(task))
            .toList();
        break;
      case 2: // Completed
        filteredTasks = categoryFiltered
            .where((task) => taskIsEffectivelyCompleted(task))
            .toList();
        break;
      default:
        filteredTasks = categoryFiltered;
    }

    // Sort by due date (closest first)
    filteredTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return filteredTasks;
  }

  void _showTodoScoreDetails(CompanyThemeData companyTheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: companyTheme.isDark
                    ? companyTheme.iconColor.withValues(alpha: 0.24)
                    : const Color(0xFFE9DED5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: companyTheme.mutedInkColor.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      height: 46,
                      width: 46,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFD199),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        color: Color(0xFF5F4E31),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Goals Score',
                        style: TextStyle(
                          fontSize: 20,
                          color: companyTheme.inkColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '$_todoScore%',
                      style: TextStyle(
                        fontSize: 24,
                        color: companyTheme.inkColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildScoreProgressRow(TaskTag.personal, companyTheme),
                const SizedBox(height: 14),
                _buildScoreProgressRow(TaskTag.professional, companyTheme),
                const SizedBox(height: 14),
                _buildScoreProgressRow(TaskTag.contribution, companyTheme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreProgressRow(
    TaskTag category,
    CompanyThemeData companyTheme,
  ) {
    final score = _categoryScore(category);
    final total = _totalGoalsForCategory(category);
    final completed = _completedGoalsForCategory(category);
    final taskValue = _taskValueForCategory(category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category.fullDisplayName,
                style: TextStyle(
                  fontSize: 15,
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$score%',
              style: TextStyle(
                fontSize: 15,
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: (score / 100).clamp(0.0, 1.0),
                  backgroundColor:
                      companyTheme.mutedInkColor.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(category.color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$completed/$total',
              style: TextStyle(
                fontSize: 12,
                color: companyTheme.mutedInkColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          total == 0
              ? 'Add goals in this category to start scoring.'
              : 'Each goal is worth ${taskValue.toStringAsFixed(taskValue == taskValue.roundToDouble() ? 0 : 1)}%.',
          style: TextStyle(
            fontSize: 12,
            color: companyTheme.mutedInkColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _showAddTaskDialog() {
    final companyTheme = _currentCompanyTheme();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final subTaskController = TextEditingController();
    final List<TaskSubItem> subTasks = [];
    DateTime selectedStartDate = DateTime.now();
    DateTime selectedDueDate = DateTime.now();
    GoalType selectedGoalType = GoalType.longTerm;
    TaskTag selectedTag = TaskTag.personal;

    showDialog(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.company(companyTheme),
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('New Goal'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: EdgeInsets.zero,
            backgroundColor: companyTheme.surfaceColor,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title field with list icon
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.list, color: companyTheme.iconColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: 'Goal title',
                            hintText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: companyTheme.mutedInkColor
                                    .withValues(alpha: 0.25),
                                width: 1.4,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: companyTheme.mutedInkColor
                                    .withValues(alpha: 0.25),
                                width: 1.4,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: companyTheme.iconColor,
                                width: 1.4,
                              ),
                            ),
                            counterText: '${titleController.text.length}/60',
                            helperText: 'Maximum 60 characters',
                          ),
                          autofocus: true,
                          maxLength: 60,
                          buildCounter: (BuildContext context,
                              {required int currentLength,
                              required bool isFocused,
                              required int? maxLength}) {
                            return null;
                          },
                          onChanged: (text) {
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description field with chat icon
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(top: 12),
                        child: Icon(Icons.chat_bubble_outline,
                            color: companyTheme.iconColor, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: descriptionController,
                          decoration: InputDecoration(
                            hintText: 'Description (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 12),
                          ),
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.flag_outlined,
                          color: companyTheme.iconColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: GoalType.values.map((goalType) {
                            final isSelected = goalType == selectedGoalType;
                            return ChoiceChip(
                              label: Text(goalType.displayName),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() {
                                  selectedGoalType = goalType;
                                  if (goalType == GoalType.everyday) {
                                    subTasks.clear();
                                  }
                                });
                              },
                              selectedColor: companyTheme.primaryColor
                                  .withValues(alpha: 0.18),
                              backgroundColor: companyTheme.surfaceColor,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? companyTheme.inkColor
                                    : companyTheme.mutedInkColor,
                                fontWeight: FontWeight.w700,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? companyTheme.primaryColor
                                    : companyTheme.mutedInkColor
                                        .withValues(alpha: 0.25),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.local_offer_outlined,
                          color: companyTheme.iconColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: companyTheme.mutedInkColor
                                  .withValues(alpha: 0.25),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: companyTheme.surfaceColor,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<TaskTag>(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              isExpanded: true,
                              value: selectedTag,
                              items: _goalCategories.map((tag) {
                                return DropdownMenuItem<TaskTag>(
                                  value: tag,
                                  // Improve layout of dropdown items to prevent overflow
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        right:
                                            8.0), // Add padding to prevent overflow
                                    child: Row(
                                      mainAxisSize: MainAxisSize
                                          .min, // Use minimum space needed
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: tag == TaskTag.none
                                                ? companyTheme.mutedInkColor
                                                : tag.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Use Flexible to allow text to wrap or shrink if needed
                                        Flexible(
                                          child: Text(
                                            tag.displayName,
                                            overflow: TextOverflow
                                                .ellipsis, // Handle text overflow
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  selectedTag = newValue!;
                                });
                              },
                              // Constrain dropdown menu width
                              menuMaxHeight: 300,
                              hint: Text(
                                'Add a goal tag',
                                style: TextStyle(
                                  color: companyTheme.mutedInkColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (selectedGoalType == GoalType.longTerm) ...[
                    _buildSubtaskEditor(
                      subTasks: subTasks,
                      controller: subTaskController,
                      setDialogState: setState,
                      companyTheme: companyTheme,
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Text(
                      'Everyday goals use the calendar inside the task card to mark each day done.',
                      style: TextStyle(
                        color: companyTheme.mutedInkColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Goal date selection
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.calendar_today,
                          color: companyTheme.iconColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: companyTheme.inkColor,
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedStartDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null &&
                                    picked != selectedStartDate) {
                                  setState(() {
                                    selectedStartDate = picked;
                                    if (selectedDueDate.isBefore(picked)) {
                                      selectedDueDate = picked;
                                    }
                                  });
                                }
                              },
                              child: Text(
                                DateFormat('EEE, MMM d, yyyy')
                                    .format(selectedStartDate),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: companyTheme.mutedInkColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.event_available,
                          color: companyTheme.iconColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: companyTheme.inkColor,
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDueDate,
                                  firstDate: selectedStartDate,
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null &&
                                    picked != selectedDueDate) {
                                  setState(() {
                                    selectedDueDate = picked;
                                    if (selectedStartDate.isAfter(picked)) {
                                      selectedStartDate = picked;
                                    }
                                  });
                                }
                              },
                              child: Text(
                                DateFormat('EEE, MMM d, yyyy')
                                    .format(selectedDueDate),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: companyTheme.mutedInkColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            actions: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ElevatedButton(
                          onPressed: () {
                            if (titleController.text.trim().isNotEmpty) {
                              _addTask(
                                Task(
                                  id: "", // Empty ID - will be set by Firestore
                                  title: titleController.text.trim(),
                                  description:
                                      descriptionController.text.trim(),
                                  goalType: selectedGoalType,
                                  startDate: selectedStartDate,
                                  dueDate: selectedDueDate,
                                  tag: selectedTag,
                                  subTasks: List<TaskSubItem>.from(subTasks),
                                ),
                              );
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: companyTheme.primaryColor,
                            foregroundColor:
                                _onSurfaceFor(companyTheme.primaryColor),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'ADD',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // CANCEL button - white with gray text (on the right)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: companyTheme.surfaceColor,
                            foregroundColor: companyTheme.mutedInkColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: BorderSide(
                                color: companyTheme.mutedInkColor
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          child: const Text(
                            'CANCEL',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _getFilteredTasks();

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        if (_isResolvingCompanyMode) {
          return Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (_useAbundanceGoalsHub) {
          return Theme(
            data: AppTheme.company(companyTheme),
            child: const GoalsHubScreen(),
          );
        }

        final scorePanelColor = companyTheme.isDark
            ? companyTheme.surfaceColor
            : const Color(0xFFFCF5EA);
        final scorePanelBorder = companyTheme.isDark
            ? companyTheme.iconColor.withValues(alpha: 0.28)
            : const Color(0xFFE9DED5);
        final searchFill = companyTheme.isDark
            ? companyTheme.surfaceColor
            : const Color(0xFFEFEEEE);

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              decoration: BoxDecoration(
                color: companyTheme.isDark
                    ? companyTheme.backgroundColor
                    : Colors.white,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildCategoryButton('All', 0, companyTheme),
                  _buildCategoryButton(
                    'Pending',
                    1,
                    companyTheme,
                    badge: _tasks
                        .where((task) => !taskIsEffectivelyCompleted(task))
                        .length,
                  ),
                  _buildCategoryButton('Completed', 2, companyTheme),
                ],
              ),
            ),
          ),
          backgroundColor: companyTheme.backgroundColor,
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Search field
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: companyTheme.inkColor),
                        cursorColor: companyTheme.iconColor,
                        decoration: InputDecoration(
                          hintText: 'Search goals...',
                          hintStyle:
                              TextStyle(color: companyTheme.mutedInkColor),
                          prefixIcon: Icon(
                            Icons.search,
                            color: companyTheme.iconColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(32),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(32),
                            borderSide: BorderSide(
                              color: companyTheme.isDark
                                  ? companyTheme.iconColor
                                      .withValues(alpha: 0.36)
                                  : Colors.transparent,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(32),
                            borderSide: BorderSide(
                              color: companyTheme.iconColor,
                              width: 1.4,
                            ),
                          ),
                          filled: true,
                          fillColor: searchFill,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: companyTheme.mutedInkColor,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          _buildGoalCategoryTab(
                            label: 'All Goals',
                            category: null,
                            companyTheme: companyTheme,
                          ),
                          for (final category in _goalCategories) ...[
                            const SizedBox(width: 8),
                            _buildGoalCategoryTab(
                              label: category.displayName,
                              category: category,
                              companyTheme: companyTheme,
                            ),
                          ],
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showTodoScoreDetails(companyTheme),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: scorePanelColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: scorePanelBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              height: 46,
                              width: 46,
                              decoration: BoxDecoration(
                                color: companyTheme.primaryColor
                                    .withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.stars_rounded,
                                color: companyTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Goals score',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: companyTheme.mutedInkColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$_completedGoalCount of $_totalGoalCount goals completed on time',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: companyTheme.inkColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'P ${_categoryScore(TaskTag.personal)}%  •  Pro ${_categoryScore(TaskTag.professional)}%  •  C ${_categoryScore(TaskTag.contribution)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: companyTheme.mutedInkColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$_todoScore%',
                              style: TextStyle(
                                fontSize: 30,
                                color: companyTheme.inkColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: companyTheme.mutedInkColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredTasks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 28,
                                    color: companyTheme.mutedInkColor,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No matching goals found'
                                        : _currentTabIndex == 2
                                            ? 'No completed goals yet'
                                            : 'No goals yet',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: companyTheme.mutedInkColor,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredTasks.length,
                              itemBuilder: (context, index) {
                                final task = filteredTasks[index];
                                final isCompleted =
                                    taskIsEffectivelyCompleted(task);
                                final progress = taskProgress(task).round();

                                return GestureDetector(
                                  onHorizontalDragEnd: (details) {
                                    if (details.primaryVelocity! < 0) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Delete Goal'),
                                          content: const Text(
                                              'Are you sure you want to delete this goal?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('CANCEL'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _deleteTask(task.id);
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: const Text(
                                                        'Goal deleted'),
                                                    action: SnackBarAction(
                                                      label: 'UNDO',
                                                      onPressed: () {
                                                        _addTask(task);
                                                      },
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: const Text('DELETE'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    // Handle swipe right (complete)
                                    else if (details.primaryVelocity! > 0) {
                                      _toggleTaskCompletion(task.id);
                                    }
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    color: companyTheme.isDark
                                        ? companyTheme.surfaceColor
                                        : Colors.white,
                                    elevation: 0.5,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: companyTheme.isDark
                                            ? companyTheme.iconColor
                                                .withValues(alpha: 0.18)
                                            : Colors.black
                                                .withValues(alpha: 0.06),
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: IntrinsicHeight(
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 5,
                                            color: task.tag == TaskTag.none
                                                ? companyTheme.mutedInkColor
                                                : task.tag.color,
                                          ),
                                          Expanded(
                                            child: ListTile(
                                              onTap: () =>
                                                  _showTaskDetails(task),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 8,
                                              ),
                                              leading: Checkbox(
                                                value:
                                                    task.subTasks.isNotEmpty &&
                                                            progress > 0 &&
                                                            progress < 100
                                                        ? null
                                                        : isCompleted,
                                                tristate:
                                                    task.subTasks.isNotEmpty,
                                                onChanged: (value) {
                                                  _toggleTaskCompletion(
                                                      task.id);
                                                },
                                                shape: const CircleBorder(),
                                                checkColor: Colors.white,
                                                activeColor:
                                                    companyTheme.iconColor,
                                                side: BorderSide(
                                                  color: companyTheme
                                                      .mutedInkColor,
                                                ),
                                              ),
                                              title: Text(
                                                task.title,
                                                style: TextStyle(
                                                  decoration: isCompleted
                                                      ? TextDecoration
                                                          .lineThrough
                                                      : null,
                                                  fontWeight: isCompleted
                                                      ? FontWeight.normal
                                                      : FontWeight.bold,
                                                  color: isCompleted
                                                      ? companyTheme
                                                          .mutedInkColor
                                                      : companyTheme.inkColor,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (task
                                                      .description.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              bottom: 8.0,
                                                              top: 4.0),
                                                      child: Text(
                                                        task.description,
                                                        style: TextStyle(
                                                          color: isCompleted
                                                              ? companyTheme
                                                                  .mutedInkColor
                                                              : companyTheme
                                                                  .inkColor
                                                                  .withValues(
                                                                      alpha:
                                                                          0.82),
                                                          decoration: isCompleted
                                                              ? TextDecoration
                                                                  .lineThrough
                                                              : null,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4.0,
                                                            bottom: 4.0),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .calendar_today,
                                                              size: 16,
                                                              color: companyTheme
                                                                  .mutedInkColor,
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                            Text(
                                                              'Start ${DateFormat('MMM d, yyyy').format(task.startDate)}',
                                                              style: TextStyle(
                                                                color: companyTheme
                                                                    .mutedInkColor,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                            height: 4),
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .event_available,
                                                              size: 16,
                                                              color: companyTheme
                                                                  .mutedInkColor,
                                                            ),
                                                            const SizedBox(
                                                                width: 4),
                                                            Text(
                                                              'End ${DateFormat('MMM d, yyyy').format(task.dueDate)}',
                                                              style: TextStyle(
                                                                color: companyTheme
                                                                    .mutedInkColor,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (task.goalType ==
                                                      GoalType.everyday)
                                                    _buildTaskDateStrip(
                                                      task: task,
                                                      companyTheme:
                                                          companyTheme,
                                                    ),
                                                  if (task.tag != TaskTag.none)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 2.0,
                                                              bottom: 4.0),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Container(
                                                            width: 8,
                                                            height: 8,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: task
                                                                  .tag.color,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 6),
                                                          Text(
                                                            task.tag
                                                                .displayName,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: task
                                                                  .tag.color,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  const SizedBox(height: 8),
                                                  _buildTaskProgressBar(
                                                    task: task,
                                                    accentColor:
                                                        task.tag == TaskTag.none
                                                            ? companyTheme
                                                                .mutedInkColor
                                                            : task.tag.color,
                                                    mutedColor: companyTheme
                                                        .mutedInkColor,
                                                    isCompleted: isCompleted,
                                                  ),
                                                  if (task.subTasks.isNotEmpty)
                                                    _buildSubtaskRows(
                                                      task: task,
                                                      titleColor:
                                                          companyTheme.inkColor,
                                                      mutedColor: companyTheme
                                                          .mutedInkColor,
                                                      accentColor: task.tag ==
                                                              TaskTag.none
                                                          ? companyTheme
                                                              .mutedInkColor
                                                          : task.tag.color,
                                                    ),
                                                ],
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.edit_outlined,
                                                      color: companyTheme
                                                          .iconColor,
                                                    ),
                                                    onPressed: () {
                                                      _editTask(task);
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.delete_outline,
                                                      color: companyTheme
                                                          .mutedInkColor,
                                                    ),
                                                    onPressed: () async {
                                                      final shouldDelete =
                                                          await showDialog<
                                                              bool>(
                                                        context: context,
                                                        builder: (context) =>
                                                            AlertDialog(
                                                          title: const Text(
                                                              'Delete Goal'),
                                                          content: const Text(
                                                              'Are you sure you want to delete this goal?'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context,
                                                                      false),
                                                              child: const Text(
                                                                  'CANCEL'),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                      context,
                                                                      true),
                                                              child: const Text(
                                                                  'DELETE'),
                                                            ),
                                                          ],
                                                        ),
                                                      );

                                                      if (shouldDelete ==
                                                          true) {
                                                        _deleteTask(task.id);
                                                      }
                                                    },
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
                            ),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddTaskDialog(),
            backgroundColor: companyTheme.isDark
                ? companyTheme.iconColor
                : const Color(0xFFEFD199),
            elevation: 2,
            shape: const CircleBorder(),
            child: Icon(
              Icons.add,
              color: companyTheme.isDark ? Colors.black : Colors.white,
            ),
          ),
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: companyTheme.isDark
                        ? companyTheme.surfaceColor
                        : companyTheme.primaryColor,
                  ),
                  child: Text(
                    'Goals',
                    style: TextStyle(
                      color: _onSurfaceFor(companyTheme.isDark
                          ? companyTheme.surfaceColor
                          : companyTheme.primaryColor),
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('Migrate Local Data to Firebase'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMigrationDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTaskDetails(Task task) {
    final companyTheme = _currentCompanyTheme();
    final startDate = DateFormat('EEE, MMM d, yyyy').format(task.startDate);
    final dueDate = DateFormat('EEE, MMM d, yyyy').format(task.dueDate);
    final completedDate = task.completedAt == null
        ? null
        : DateFormat('EEE, MMM d, yyyy • h:mm a').format(task.completedAt!);
    DateTime visibleMonth = DateTime(task.startDate.year, task.startDate.month);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Theme(
          data: AppTheme.company(companyTheme),
          child: AlertDialog(
            title: const Text('Goal Details'),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            backgroundColor: companyTheme.surfaceColor,
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTaskDetailRow(
                        icon: Icons.list,
                        label: 'Goal title',
                        value: task.title,
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                      ),
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: Icons.chat_bubble_outline,
                        label: 'Description',
                        value: task.description.trim().isEmpty
                            ? 'No description added.'
                            : task.description.trim(),
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                      ),
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: Icons.local_offer_outlined,
                        label: 'Tag',
                        value: task.tag.fullDisplayName,
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                        accentColor: task.tag == TaskTag.none
                            ? Colors.grey
                            : task.tag.color,
                      ),
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: Icons.calendar_today,
                        label: 'Start Date',
                        value: startDate,
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                      ),
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: Icons.event_available,
                        label: 'End Date',
                        value: dueDate,
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                      ),
                      if (task.goalType == GoalType.everyday) ...[
                        const SizedBox(height: 16),
                        _buildTaskCalendarPanel(
                          task: task,
                          companyTheme: companyTheme,
                          visibleMonth: visibleMonth,
                          onDayChanged: () => setDialogState(() {}),
                          onPreviousMonth: () {
                            setDialogState(() {
                              visibleMonth = DateTime(
                                  visibleMonth.year, visibleMonth.month - 1);
                            });
                          },
                          onNextMonth: () {
                            setDialogState(() {
                              visibleMonth = DateTime(
                                  visibleMonth.year, visibleMonth.month + 1);
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: Icons.insights_outlined,
                        label: 'Progress',
                        value: '${taskProgress(task).round()}%',
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                        accentColor: task.tag == TaskTag.none
                            ? Colors.grey
                            : task.tag.color,
                      ),
                      const SizedBox(height: 12),
                      _buildTaskProgressBar(
                        task: task,
                        accentColor: task.tag == TaskTag.none
                            ? Colors.grey
                            : task.tag.color,
                        mutedColor: const Color(0xFF6E625B),
                        isCompleted: taskIsEffectivelyCompleted(task),
                      ),
                      if (task.goalType == GoalType.longTerm &&
                          task.subTasks.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildSubtaskRows(
                          task: task,
                          titleColor: companyTheme.inkColor,
                          mutedColor: companyTheme.mutedInkColor,
                          accentColor: task.tag == TaskTag.none
                              ? Colors.grey
                              : task.tag.color,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildTaskDetailRow(
                        icon: taskIsEffectivelyCompleted(task)
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        label: 'Status',
                        value: taskIsEffectivelyCompleted(task)
                            ? 'Completed'
                            : 'Pending',
                        labelColor: companyTheme.mutedInkColor,
                        valueColor: companyTheme.inkColor,
                        accentColor: taskIsEffectivelyCompleted(task)
                            ? const Color(0xFF6F8A5F)
                            : Colors.grey,
                      ),
                      if (completedDate != null) ...[
                        const SizedBox(height: 16),
                        _buildTaskDetailRow(
                          icon: Icons.event_available,
                          label: 'Completed At',
                          value: completedDate,
                          labelColor: companyTheme.mutedInkColor,
                          valueColor: companyTheme.inkColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CLOSE'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _editTask(task);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('EDIT'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: companyTheme.primaryColor,
                  foregroundColor: _onSurfaceFor(companyTheme.primaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
    Color? accentColor,
  }) {
    final effectiveAccent = accentColor ?? Colors.grey;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: effectiveAccent, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: valueColor,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _editTask(Task task) {
    final companyTheme = _currentCompanyTheme();
    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(text: task.description);
    final subTaskController = TextEditingController();
    final List<TaskSubItem> subTasks = task.subTasks
        .map(
          (subTask) => subTask.copyWith(),
        )
        .toList();
    GoalType selectedGoalType = task.goalType;
    DateTime selectedStartDate = task.startDate;
    DateTime selectedDueDate = task.dueDate;
    TaskTag selectedTag =
        _goalCategories.contains(task.tag) ? task.tag : TaskTag.personal;

    showDialog(
      context: context,
      builder: (context) => Theme(
        data: AppTheme.company(companyTheme),
        child: StatefulBuilder(
          builder: (context, setState) {
            final colorScheme = Theme.of(context).colorScheme;
            final surfaceColor = colorScheme.surface;
            final textPrimaryColor = colorScheme.onSurface;
            final textSecondaryColor = colorScheme.onSurfaceVariant;
            final borderColor = colorScheme.outlineVariant;
            final accentColor = colorScheme.primary;
            final onAccentColor = colorScheme.onPrimary;

            return AlertDialog(
              title: const Text('Edit Goal'),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              actionsPadding: EdgeInsets.zero,
              backgroundColor: surfaceColor,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title field with list icon
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.list, color: accentColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: titleController,
                            decoration: InputDecoration(
                              labelText: 'Goal title',
                              hintText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: borderColor, width: 1.4),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: borderColor, width: 1.4),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: accentColor, width: 1.4),
                              ),
                              counterText: '${titleController.text.length}/60',
                              helperText: 'Maximum 60 characters',
                              labelStyle: TextStyle(color: textSecondaryColor),
                              helperStyle: TextStyle(color: textSecondaryColor),
                            ),
                            autofocus: true,
                            maxLength: 60,
                            buildCounter: (BuildContext context,
                                {required int currentLength,
                                required bool isFocused,
                                required int? maxLength}) {
                              return null;
                            },
                            onChanged: (text) {
                              setState(() {});
                            },
                            style: TextStyle(color: textPrimaryColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description field with chat icon
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.only(top: 12),
                          child: Icon(Icons.chat_bubble_outline,
                              color: accentColor, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: descriptionController,
                            decoration: InputDecoration(
                              hintText: 'Description (optional)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: accentColor, width: 1.4),
                              ),
                              hintStyle: TextStyle(color: textSecondaryColor),
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 12),
                            ),
                            maxLines: 3,
                            style: TextStyle(color: textPrimaryColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.flag_outlined, color: accentColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: GoalType.values.map((goalType) {
                              final isSelected = goalType == selectedGoalType;
                              return ChoiceChip(
                                label: Text(goalType.displayName),
                                selected: isSelected,
                                onSelected: (_) {
                                  setState(() {
                                    selectedGoalType = goalType;
                                    if (goalType == GoalType.everyday) {
                                      subTasks.clear();
                                    }
                                  });
                                },
                                selectedColor:
                                    accentColor.withValues(alpha: 0.18),
                                backgroundColor: surfaceColor,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? textPrimaryColor
                                      : textSecondaryColor,
                                  fontWeight: FontWeight.w700,
                                ),
                                side: BorderSide(
                                  color: isSelected
                                      ? accentColor
                                      : textSecondaryColor.withValues(
                                          alpha: 0.25,
                                        ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer_outlined,
                            color: accentColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(8),
                              color: surfaceColor,
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<TaskTag>(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                isExpanded: true,
                                value: selectedTag,
                                items: _goalCategories.map((tag) {
                                  return DropdownMenuItem<TaskTag>(
                                    value: tag,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: tag == TaskTag.none
                                                  ? textSecondaryColor
                                                  : tag.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              tag.displayName,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedTag = newValue!;
                                  });
                                },
                                menuMaxHeight: 300,
                                hint: Text(
                                  'Add a goal tag',
                                  style: TextStyle(color: textSecondaryColor),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (selectedGoalType == GoalType.longTerm) ...[
                      _buildSubtaskEditor(
                        subTasks: subTasks,
                        controller: subTaskController,
                        setDialogState: setState,
                        companyTheme: companyTheme,
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'Everyday goals use the calendar inside the task card to mark each day done.',
                        style: TextStyle(
                          color: textSecondaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Goal date selection
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.calendar_today,
                            color: accentColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start Date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimaryColor,
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedStartDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null &&
                                      picked != selectedStartDate) {
                                    setState(() {
                                      selectedStartDate = picked;
                                      if (selectedDueDate.isBefore(picked)) {
                                        selectedDueDate = picked;
                                      }
                                    });
                                  }
                                },
                                child: Text(
                                  DateFormat('EEE, MMM d, yyyy')
                                      .format(selectedStartDate),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: textSecondaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.event_available,
                            color: accentColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'End Date',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimaryColor,
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDueDate,
                                    firstDate: selectedStartDate,
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null &&
                                      picked != selectedDueDate) {
                                    setState(() {
                                      selectedDueDate = picked;
                                      if (selectedStartDate.isAfter(picked)) {
                                        selectedStartDate = picked;
                                      }
                                    });
                                  }
                                },
                                child: Text(
                                  DateFormat('EEE, MMM d, yyyy')
                                      .format(selectedDueDate),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: textSecondaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // SAVE button
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ElevatedButton(
                            onPressed: () {
                              if (titleController.text.trim().isNotEmpty) {
                                final updatedTask = Task(
                                  id: task.id,
                                  title: titleController.text.trim(),
                                  description:
                                      descriptionController.text.trim(),
                                  goalType: selectedGoalType,
                                  startDate: selectedStartDate,
                                  dueDate: selectedDueDate,
                                  tag: selectedTag,
                                  createdAt: task.createdAt,
                                  updatedAt: DateTime.now(),
                                  completedAt: task.completedAt,
                                  completionDates:
                                      List<DateTime>.from(task.completionDates),
                                  subTasks: List<TaskSubItem>.from(subTasks),
                                );

                                _updateTask(updatedTask);
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: onAccentColor,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'SAVE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // CANCEL button
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: surfaceColor,
                              foregroundColor: textSecondaryColor,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                                side: BorderSide(color: borderColor),
                              ),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
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

  void _updateTask(Task task) async {
    try {
      syncTaskCompletion(task, completedAt: task.completedAt);

      // Update in Firestore
      await _repository.updateTask(task);
      await _scheduleTaskNotification(task);
      await _syncTodoListScore();

      // Update local state for immediate UI feedback
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = task;
        }
      });

      // Show a confirmation message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goal updated successfully')),
      );
    } catch (e) {
      print('Error updating task: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update goal. Please try again.')),
      );
      // If update fails, reload tasks to ensure UI is in sync with database
      await _loadTasks();
    }
  }

  Widget _buildGoalCategoryTab({
    required String label,
    required TaskTag? category,
    required CompanyThemeData companyTheme,
  }) {
    final isSelected = _selectedGoalCategory == category;
    final count =
        category == null ? _totalGoalCount : _totalGoalsForCategory(category);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGoalCategory = category;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? companyTheme.iconColor
              : companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? companyTheme.iconColor
                : companyTheme.mutedInkColor.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category != null) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (companyTheme.isDark ? Colors.black : Colors.white)
                      : category.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (companyTheme.isDark ? Colors.black : Colors.white)
                    : companyTheme.inkColor,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$count',
              style: TextStyle(
                color: isSelected
                    ? (companyTheme.isDark
                        ? Colors.black.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.78))
                    : companyTheme.mutedInkColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryButton(
    String category,
    int index,
    CompanyThemeData companyTheme, {
    int? badge,
  }) {
    bool isSelected = index == _currentTabIndex;

    double buttonWidth;
    if (category == 'All') {
      buttonWidth = 80;
    } else if (category == 'Pending') {
      buttonWidth = 132;
    } else {
      // Completed
      buttonWidth = 132;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        width: buttonWidth,
        decoration: BoxDecoration(
          color: isSelected
              ? companyTheme.iconColor
              : companyTheme.isDark
                  ? companyTheme.surfaceColor
                  : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: companyTheme.isDark
                ? companyTheme.iconColor.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: companyTheme.iconColor.withValues(alpha: 0.32),
                      blurRadius: 5,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                category,
                style: TextStyle(
                  color: isSelected
                      ? (companyTheme.isDark ? Colors.black : Colors.white)
                      : companyTheme.inkColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (companyTheme.isDark
                            ? Colors.black.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.3))
                        : companyTheme.iconColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badge.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
