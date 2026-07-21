/// Laravel-backed access for the Goals feature.
library;

import 'dart:async';

import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

DateTime _parseDate(Object? value) {
  if (value == null) return DateTime.now();
  return DateTime.tryParse(value.toString()) ?? DateTime.now();
}

class GoalSummary {
  const GoalSummary({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.title,
    required this.description,
    required this.notes,
    required this.status,
    required this.progress,
    required this.category,
    required this.goalType,
    required this.targetPeriod,
    required this.direction,
    required this.targetValue,
    required this.currentValue,
    required this.unit,
    required this.startDate,
    required this.targetDate,
    required this.completedAt,
  });

  factory GoalSummary.fromJson(Map<String, dynamic> json) {
    return GoalSummary(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      companyId: json['companyId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      notes: json['notes']?.toString(),
      status: GoalStatus.fromCode(json['status']?.toString()),
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      category: GoalCategory.fromCode(json['category']?.toString()),
      goalType: GoalType.fromCode(json['goalType']?.toString()),
      targetPeriod: TargetPeriod.fromCode(json['targetPeriod']?.toString()),
      direction: GoalDirection.fromCode(json['direction']?.toString()),
      targetValue: (json['targetValue'] as num?)?.toDouble() ?? 0,
      currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0,
      unit: json['unit']?.toString() ?? '',
      startDate: _parseDate(json['startDate']),
      targetDate: _parseDate(json['targetDate']),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
    );
  }

  final String id;
  final String userId;
  final String companyId;
  final String title;
  final String? description;
  final String? notes;
  final GoalStatus status;
  final int progress;
  final GoalCategory category;
  final GoalType goalType;
  final TargetPeriod targetPeriod;
  final GoalDirection direction;
  final double targetValue;
  final double currentValue;
  final String unit;
  final DateTime startDate;
  final DateTime targetDate;
  final DateTime? completedAt;

  double? get score => scoreGoal(ScorableGoal(
        status: status,
        progress: progress,
        category: category,
        goalType: goalType,
        targetValue: targetValue,
        currentValue: currentValue,
      ));

  GoalRank get rank => rankForPercent(progress);

  int get daysUntilDue => daysUntil(targetDate);

  bool get isOverdue =>
      status != GoalStatus.completed &&
      status != GoalStatus.abandoned &&
      daysUntilDue < 0;

  double get periodTarget =>
      goalType == GoalType.merit && targetPeriod != TargetPeriod.none
          ? perPeriodTarget(
              targetValue, currentValue, daysUntilDue, targetPeriod.days)
          : 0;
}

class ActionPlanItem {
  const ActionPlanItem({
    required this.id,
    required this.title,
    required this.status,
    required this.sortOrder,
    this.dueDate,
    this.completedAt,
  });

  factory ActionPlanItem.fromJson(Map<String, dynamic> json) {
    return ActionPlanItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      status: ActionPlanStatus.fromCode(json['status']?.toString()),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.tryParse(json['dueDate'].toString()),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.tryParse(json['completedAt'].toString()),
    );
  }

  final String id;
  final String title;
  final ActionPlanStatus status;
  final int sortOrder;
  final DateTime? dueDate;
  final DateTime? completedAt;
}

class GoalUpdateEntry {
  const GoalUpdateEntry({
    required this.id,
    required this.authorId,
    required this.progressFrom,
    required this.progressTo,
    required this.statusFrom,
    required this.statusTo,
    this.note,
    this.createdAt,
  });

  factory GoalUpdateEntry.fromJson(Map<String, dynamic> json) {
    return GoalUpdateEntry(
      id: json['id']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      progressFrom: (json['progressFrom'] as num?)?.toInt() ?? 0,
      progressTo: (json['progressTo'] as num?)?.toInt() ?? 0,
      statusFrom: GoalStatus.fromCode(json['statusFrom']?.toString()),
      statusTo: GoalStatus.fromCode(json['statusTo']?.toString()),
      note: json['note']?.toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  final String id;
  final String authorId;
  final int progressFrom;
  final int progressTo;
  final GoalStatus statusFrom;
  final GoalStatus statusTo;
  final String? note;
  final DateTime? createdAt;
}

class GoalCommentItem {
  const GoalCommentItem({
    required this.id,
    required this.authorId,
    required this.body,
    required this.isPrivate,
    this.createdAt,
  });

  factory GoalCommentItem.fromJson(Map<String, dynamic> json) {
    return GoalCommentItem(
      id: json['id']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      isPrivate: json['isPrivate'] == true,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
    );
  }

  final String id;
  final String authorId;
  final String body;
  final bool isPrivate;
  final DateTime? createdAt;
}

class MeritLogItem {
  const MeritLogItem({
    required this.id,
    required this.date,
    required this.amount,
  });

  factory MeritLogItem.fromJson(Map<String, dynamic> json) {
    return MeritLogItem(
      id: json['id']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String date;
  final double amount;
}

List<GoalCategory> requiredGoalGaps(List<GoalSummary> goals) {
  final held = goals
      .where((g) => g.status != GoalStatus.abandoned)
      .map((g) => g.category)
      .toSet();
  return GoalCategory.values.where((c) => !held.contains(c)).toList();
}

class GoalsService {
  GoalsService([Object? legacyFirestore]);

  final ApiClient _api = ApiClient.instance;

  String? get _token => AuthService.instance.currentSession?.token;

  Stream<T> _poll<T>(
    Future<T> Function() fetch, {
    required T fallback,
    Duration interval = const Duration(seconds: 3),
  }) async* {
    while (true) {
      try {
        yield await fetch();
      } catch (_) {
        yield fallback;
      }
      await Future.delayed(interval);
    }
  }

  Future<List<GoalSummary>> _fetchGoals(String uid) async {
    final response = await _api.getJson(
      '/api/goals?userId=$uid',
      token: _token,
    );
    final raw = response['goals'];
    if (raw is! List) return const <GoalSummary>[];
    return raw
        .whereType<Map>()
        .map((goal) => GoalSummary.fromJson(Map<String, dynamic>.from(goal)))
        .toList()
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
  }

  Future<GoalSummary?> _fetchGoal(String goalId) async {
    try {
      final response = await _api.getJson('/api/goals/$goalId', token: _token);
      final raw = response['goal'];
      if (raw is! Map<String, dynamic>) return null;
      return GoalSummary.fromJson(raw);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ActionPlanItem>> _fetchPlans(String goalId) async {
    final response = await _api.getJson('/api/goals/$goalId/tasks', token: _token);
    final raw = response['tasks'];
    if (raw is! List) return const <ActionPlanItem>[];
    return raw
        .whereType<Map>()
        .map((task) => ActionPlanItem.fromJson(Map<String, dynamic>.from(task)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<List<GoalUpdateEntry>> _fetchUpdates(String goalId) async {
    final response = await _api.getJson('/api/goals/$goalId/updates', token: _token);
    final raw = response['updates'];
    if (raw is! List) return const <GoalUpdateEntry>[];
    return raw
        .whereType<Map>()
        .map((item) => GoalUpdateEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<GoalCommentItem>> _fetchComments(String goalId) async {
    final response = await _api.getJson('/api/goals/$goalId/comments', token: _token);
    final raw = response['comments'];
    if (raw is! List) return const <GoalCommentItem>[];
    return raw
        .whereType<Map>()
        .map((item) => GoalCommentItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<MeritLogItem>> _fetchMerits(String goalId) async {
    final response = await _api.getJson('/api/goals/$goalId/merits', token: _token);
    final raw = response['merits'];
    if (raw is! List) return const <MeritLogItem>[];
    return raw
        .whereType<Map>()
        .map((item) => MeritLogItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Stream<List<GoalSummary>> watchGoals(String uid) =>
      _poll(() => _fetchGoals(uid), fallback: const <GoalSummary>[]);

  Stream<GoalSummary?> watchGoal(String goalId) =>
      _poll(() => _fetchGoal(goalId), fallback: null);

  Stream<List<ActionPlanItem>> watchPlans(String goalId) =>
      _poll(() => _fetchPlans(goalId), fallback: const <ActionPlanItem>[]);

  Stream<List<GoalUpdateEntry>> watchUpdates(String goalId) =>
      _poll(() => _fetchUpdates(goalId), fallback: const <GoalUpdateEntry>[]);

  Stream<List<GoalCommentItem>> watchComments(String goalId) =>
      _poll(() => _fetchComments(goalId), fallback: const <GoalCommentItem>[]);

  Stream<List<MeritLogItem>> watchMerits(String goalId) =>
      _poll(() => _fetchMerits(goalId), fallback: const <MeritLogItem>[]);

  Future<String> createGoal({
    required String uid,
    required GoalCategory category,
    required String title,
    String? description,
    String? notes,
    required DateTime targetDate,
    GoalType goalType = GoalType.merit,
    GoalDirection direction = GoalDirection.gain,
    double targetValue = 0,
    double currentValue = 0,
    String unit = '',
    TargetPeriod targetPeriod = TargetPeriod.none,
    List<String> planTitles = const [],
  }) async {
    final response = await _api.postJson(
      '/api/goals',
      {
        'category': category.code,
        'title': title.trim(),
        'description': description,
        'notes': notes,
        'status': GoalStatus.notStarted.code,
        'goal_type': goalType.code,
        'direction': direction.code,
        'target_value': targetValue,
        'current_value': currentValue,
        'unit': unit.trim(),
        'target_period': targetPeriod.code,
        'target_date': isoDay(targetDate),
        'plan_titles': planTitles,
      },
      token: _token,
    );
    final raw = response['goal'];
    if (raw is Map<String, dynamic>) {
      return GoalSummary.fromJson(raw).id;
    }
    throw ApiException(500, 'Goal response was invalid.');
  }

  Future<void> updateGoal({
    required String goalId,
    required String actorId,
    String? title,
    String? description,
    String? notes,
    GoalStatus? status,
    DateTime? targetDate,
    GoalDirection? direction,
    double? targetValue,
    double? currentValue,
    String? unit,
    GoalType? goalType,
    TargetPeriod? targetPeriod,
  }) async {
    final payload = <String, dynamic>{
      if (title != null) 'title': title.trim(),
      if (description != null || notes != null) 'description': description,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status.code,
      if (targetDate != null) 'target_date': isoDay(targetDate),
      if (direction != null) 'direction': direction.code,
      if (targetValue != null) 'target_value': targetValue,
      if (currentValue != null) 'current_value': currentValue,
      if (unit != null) 'unit': unit.trim(),
      if (goalType != null) 'goal_type': goalType.code,
      if (targetPeriod != null) 'target_period': targetPeriod.code,
    };

    await _api.patchJson(
      '/api/goals/$goalId',
      payload,
      token: _token,
    );
  }

  Future<void> setGoalMeasure({
    required String goalId,
    required String actorId,
    required double currentValue,
  }) async {
    await _api.postJson(
      '/api/goals/$goalId/measure',
      {'current_value': currentValue},
      token: _token,
    );
  }

  Future<String> addActionPlan({
    required String goalId,
    required String title,
    required String actorId,
  }) async {
    final response = await _api.postJson(
      '/api/goals/$goalId/tasks',
      {'title': title},
      token: _token,
    );
    final raw = response['task'];
    if (raw is Map<String, dynamic>) {
      return ActionPlanItem.fromJson(raw).id;
    }
    throw ApiException(500, 'Task response was invalid.');
  }

  Future<void> setActionPlanStatus({
    required String goalId,
    required String planId,
    required ActionPlanStatus status,
    required String actorId,
  }) async {
    await _api.patchJson(
      '/api/goals/$goalId/tasks/$planId',
      {'status': status.code},
      token: _token,
    );
  }

  Future<void> deleteActionPlan({
    required String goalId,
    required String planId,
    required String actorId,
  }) async {
    await _api.deleteJson(
      '/api/goals/$goalId/tasks/$planId',
      token: _token,
    );
  }

  Future<void> addComment({
    required String goalId,
    required String authorId,
    required String body,
    bool isPrivate = false,
  }) async {
    await _api.postJson(
      '/api/goals/$goalId/comments',
      {
        'body': body.trim(),
        'is_private': isPrivate,
      },
      token: _token,
    );
  }

  Future<void> logMeritTarget({
    required String goalId,
    required String actorId,
  }) async {
    await _api.postJson(
      '/api/goals/$goalId/merits/target',
      const <String, dynamic>{},
      token: _token,
    );
  }

  Future<void> goExtraMile({
    required String goalId,
    required String actorId,
    required double amount,
  }) async {
    await _api.postJson(
      '/api/goals/$goalId/merits/extra',
      {'amount': amount},
      token: _token,
    );
  }

  Future<void> deleteGoal(String goalId) async {
    await _api.deleteJson(
      '/api/goals/$goalId',
      token: _token,
    );
  }
}
