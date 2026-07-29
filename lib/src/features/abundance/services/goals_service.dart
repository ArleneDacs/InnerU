/// Laravel-backed access for the Goals feature.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  GoalsService([FirebaseFirestore? legacyFirestore])
      : _legacyFirestore = legacyFirestore;

  final ApiClient _api = ApiClient.instance;
  final FirebaseFirestore? _legacyFirestore;

  String? get _token => AuthService.instance.currentSession?.token;
  bool get _usesLegacyFirestore => _legacyFirestore != null;
  FirebaseFirestore get _firestore =>
      _legacyFirestore ??
      (throw StateError('Legacy Firestore store is not configured.'));

  CollectionReference<Map<String, dynamic>> get _goals =>
      _firestore.collection('goals');

  DocumentReference<Map<String, dynamic>> _goalDoc(String goalId) =>
      _goals.doc(goalId);

  Future<String> _legacyUserCompanyId(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data == null) return '';
    final activeCompanyId = data['activeCompanyId']?.toString().trim();
    if (activeCompanyId != null && activeCompanyId.isNotEmpty) {
      return activeCompanyId;
    }
    final companyId = data['companyId']?.toString().trim();
    if (companyId != null && companyId.isNotEmpty) {
      return companyId;
    }
    return '';
  }

  Map<String, dynamic> _goalPayload({
    required String id,
    required String uid,
    required String companyId,
    required GoalCategory category,
    required String title,
    required String? description,
    required String? notes,
    required GoalStatus status,
    required GoalType goalType,
    required GoalDirection direction,
    required double targetValue,
    required double currentValue,
    required String unit,
    required TargetPeriod targetPeriod,
    required DateTime startDate,
    required DateTime targetDate,
    required int progress,
    required DateTime? completedAt,
  }) {
    return {
      'id': id,
      'userId': uid,
      'companyId': companyId,
      'title': title,
      'description': description,
      'notes': notes,
      'status': status.code,
      'progress': progress,
      'category': category.code,
      'goalType': goalType.code,
      'targetPeriod': targetPeriod.code,
      'direction': direction.code,
      'targetValue': targetValue,
      'currentValue': currentValue,
      'unit': unit,
      'startDate': isoDay(startDate),
      'targetDate': isoDay(targetDate),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  int _calculateMeritProgress({
    required GoalStatus status,
    required double targetValue,
    required double currentValue,
    int fallback = 0,
  }) {
    if (status == GoalStatus.completed) {
      return 100;
    }
    if (status == GoalStatus.abandoned) {
      return fallback;
    }
    if (targetValue > 0) {
      return ((currentValue / targetValue) * 100).clamp(0, 100).round();
    }
    return fallback;
  }

  Future<int> _calculateMilestoneProgress(String goalId) async {
    final plansSnapshot =
        await _goalDoc(goalId).collection('tasks').orderBy('sortOrder').get();
    final plans = plansSnapshot.docs
        .map((doc) =>
            ActionPlanStatus.fromCode(doc.data()['status']?.toString()))
        .toList();
    if (plans.isEmpty) {
      return 0;
    }
    final total = plans.fold<int>(0, (acc, status) => acc + status.weight);
    return (total / plans.length).round();
  }

  Future<void> _syncLegacyGoalProgress(String goalId) async {
    final ref = _goalDoc(goalId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) return;

    final status = GoalStatus.fromCode(data['status']?.toString());
    final goalType = GoalType.fromCode(data['goalType']?.toString());
    final targetValue = (data['targetValue'] as num?)?.toDouble() ?? 0;
    final currentValue = (data['currentValue'] as num?)?.toDouble() ?? 0;
    final storedProgress = (data['progress'] as num?)?.toInt() ?? 0;

    var progress = storedProgress;
    if (goalType == GoalType.merit) {
      progress = _calculateMeritProgress(
        status: status,
        targetValue: targetValue,
        currentValue: currentValue,
        fallback: storedProgress,
      );
    } else {
      progress = await _calculateMilestoneProgress(goalId);
    }

    DateTime? completedAt;
    if (status == GoalStatus.completed) {
      completedAt = DateTime.tryParse(data['completedAt']?.toString() ?? '') ??
          DateTime.now();
      progress = 100;
    }

    await ref.update({
      'progress': progress,
      'completedAt': completedAt?.toIso8601String(),
    });
  }

  Stream<List<GoalSummary>> _legacyWatchGoals(String uid) {
    return _goals.where('userId', isEqualTo: uid).snapshots().map((snapshot) {
      final goals = snapshot.docs
          .map((doc) => GoalSummary.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList()
        ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
      return goals;
    });
  }

  Stream<GoalSummary?> _legacyWatchGoal(String goalId) {
    return _goalDoc(goalId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;
      return GoalSummary.fromJson({
        ...data,
        'id': snapshot.id,
      });
    });
  }

  Stream<List<ActionPlanItem>> _legacyWatchPlans(String goalId) {
    return _goalDoc(goalId).collection('tasks').snapshots().map((snapshot) {
      final plans = snapshot.docs
          .map((doc) => ActionPlanItem.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return plans;
    });
  }

  Stream<List<GoalUpdateEntry>> _legacyWatchUpdates(String goalId) {
    return _goalDoc(goalId).collection('updates').snapshots().map((snapshot) {
      final updates = snapshot.docs
          .map((doc) => GoalUpdateEntry.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList()
        ..sort((a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      return updates;
    });
  }

  Stream<List<GoalCommentItem>> _legacyWatchComments(String goalId) {
    return _goalDoc(goalId).collection('comments').snapshots().map((snapshot) {
      final comments = snapshot.docs
          .map((doc) => GoalCommentItem.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();
      return comments;
    });
  }

  Stream<List<MeritLogItem>> _legacyWatchMerits(String goalId) {
    return _goalDoc(goalId).collection('merits').snapshots().map((snapshot) {
      final merits = snapshot.docs
          .map((doc) => MeritLogItem.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();
      return merits;
    });
  }

  Future<void> _legacyDeleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> _legacyRecordUpdate({
    required String goalId,
    required String actorId,
    required int progressFrom,
    required int progressTo,
    required GoalStatus statusFrom,
    required GoalStatus statusTo,
    String? note,
  }) async {
    await _goalDoc(goalId).collection('updates').add({
      'authorId': actorId,
      'progressFrom': progressFrom,
      'progressTo': progressTo,
      'statusFrom': statusFrom.code,
      'statusTo': statusTo.code,
      'note': note,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  String _legacyPeriodBucket(
    DateTime startDate,
    TargetPeriod period,
    DateTime now,
  ) {
    if (period.days <= 0) return '';
    final anchor = DateTime(startDate.year, startDate.month, startDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceStart = today.difference(anchor).inDays;
    final bucket = daysSinceStart ~/ period.days;
    return '${isoDay(anchor)}:$bucket:${period.days}';
  }

  Future<String> _legacyCreateGoal({
    required String uid,
    required GoalCategory category,
    required String title,
    String? description,
    String? notes,
    DateTime? startDate,
    required DateTime targetDate,
    GoalType goalType = GoalType.merit,
    GoalDirection direction = GoalDirection.gain,
    double targetValue = 0,
    double currentValue = 0,
    String unit = '',
    TargetPeriod targetPeriod = TargetPeriod.none,
    List<String> planTitles = const [],
  }) async {
    final goalRef = _goalDoc(_goals.doc().id);
    final id = goalRef.id;
    final companyId = await _legacyUserCompanyId(uid);
    final isMilestone = goalType == GoalType.milestone;
    final effectiveTargetPeriod =
        isMilestone ? TargetPeriod.none : targetPeriod;
    final effectiveTargetValue = isMilestone ? 0.0 : targetValue;
    final effectiveCurrentValue = isMilestone ? 0.0 : currentValue;
    final status = GoalStatus.notStarted;

    final progress = isMilestone
        ? 0
        : _calculateMeritProgress(
            status: status,
            targetValue: effectiveTargetValue,
            currentValue: effectiveCurrentValue,
          );

    await goalRef.set(
      _goalPayload(
        id: id,
        uid: uid,
        companyId: companyId,
        category: category,
        title: title.trim(),
        description:
            description?.trim().isEmpty == true ? null : description?.trim(),
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        status: status,
        goalType: goalType,
        direction: direction,
        targetValue: effectiveTargetValue,
        currentValue: effectiveCurrentValue,
        unit: unit.trim(),
        targetPeriod: effectiveTargetPeriod,
        startDate: startDate ?? DateTime.now(),
        targetDate: targetDate,
        progress: progress,
        completedAt: null,
      ),
    );

    if (isMilestone) {
      var sortOrder = 0;
      for (final rawTitle in planTitles) {
        final cleaned = rawTitle.trim();
        if (cleaned.isEmpty) continue;
        await goalRef.collection('tasks').add({
          'title': cleaned,
          'status': ActionPlanStatus.notStarted.code,
          'sortOrder': sortOrder,
          'dueDate': null,
          'completedAt': null,
          'isComplete': false,
        });
        sortOrder += 1;
      }
      await _syncLegacyGoalProgress(id);
    }

    return id;
  }

  Future<void> _legacyUpdateGoal({
    required String goalId,
    required String actorId,
    String? title,
    String? description,
    String? notes,
    GoalStatus? status,
    DateTime? startDate,
    DateTime? targetDate,
    GoalDirection? direction,
    double? targetValue,
    double? currentValue,
    String? unit,
    GoalType? goalType,
    TargetPeriod? targetPeriod,
  }) async {
    final ref = _goalDoc(goalId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) {
      throw ApiException(404, 'Goal not found.');
    }

    final before = Map<String, dynamic>.from(data);
    final updated = Map<String, dynamic>.from(before);

    if (title != null) updated['title'] = title.trim();
    if (description != null) {
      updated['description'] = description.trim();
    }
    if (notes != null) {
      updated['notes'] = notes.trim();
    }
    if (status != null) updated['status'] = status.code;
    if (startDate != null) updated['startDate'] = isoDay(startDate);
    if (targetDate != null) updated['targetDate'] = isoDay(targetDate);
    if (direction != null) updated['direction'] = direction.code;
    if (targetValue != null) updated['targetValue'] = targetValue;
    if (currentValue != null) updated['currentValue'] = currentValue;
    if (unit != null) updated['unit'] = unit.trim();
    if (goalType != null) updated['goalType'] = goalType.code;
    if (targetPeriod != null) updated['targetPeriod'] = targetPeriod.code;

    final previousProgress = (before['progress'] as num?)?.toInt() ?? 0;
    final previousStatus = GoalStatus.fromCode(before['status']?.toString());

    final effectiveGoalType =
        GoalType.fromCode(updated['goalType']?.toString());
    final effectiveStatus = GoalStatus.fromCode(updated['status']?.toString());
    final effectiveTargetValue =
        (updated['targetValue'] as num?)?.toDouble() ?? 0;
    final effectiveCurrentValue =
        (updated['currentValue'] as num?)?.toDouble() ?? 0;

    var progress = previousProgress;
    if (effectiveGoalType == GoalType.milestone) {
      progress = await _calculateMilestoneProgress(goalId);
      updated['targetPeriod'] = TargetPeriod.none.code;
      updated['targetValue'] = 0.0;
      updated['currentValue'] = 0.0;
    } else {
      progress = _calculateMeritProgress(
        status: effectiveStatus,
        targetValue: effectiveTargetValue,
        currentValue: effectiveCurrentValue,
        fallback: previousProgress,
      );
    }

    if (effectiveStatus == GoalStatus.completed) {
      updated['completedAt'] =
          (before['completedAt']?.toString().isNotEmpty == true)
              ? before['completedAt']
              : DateTime.now().toIso8601String();
      progress = 100;
    } else {
      updated['completedAt'] = null;
    }

    updated['progress'] = progress;
    await ref.set(updated);

    if (progress != previousProgress || effectiveStatus != previousStatus) {
      await _legacyRecordUpdate(
        goalId: goalId,
        actorId: actorId,
        progressFrom: previousProgress,
        progressTo: progress,
        statusFrom: previousStatus,
        statusTo: effectiveStatus,
      );
    }
  }

  Future<void> _legacySetGoalMeasure({
    required String goalId,
    required String actorId,
    required double currentValue,
  }) async {
    final snapshot = await _goalDoc(goalId).get();
    final data = snapshot.data();
    if (data == null) {
      throw ApiException(404, 'Goal not found.');
    }

    if (GoalType.fromCode(data['goalType']?.toString()) == GoalType.milestone) {
      throw StateError('Milestone goals do not use a numeric measure.');
    }

    await _legacyUpdateGoal(
      goalId: goalId,
      actorId: actorId,
      currentValue: currentValue,
    );
  }

  Future<String> _legacyAddActionPlan({
    required String goalId,
    required String title,
    required String actorId,
  }) async {
    final ref = _goalDoc(goalId).collection('tasks');
    final snapshot = await ref.get();
    final sortOrder = snapshot.docs.isEmpty
        ? 0
        : snapshot.docs
                .map((doc) => (doc.data()['sortOrder'] as num?)?.toInt() ?? 0)
                .reduce((a, b) => a > b ? a : b) +
            1;
    final doc = ref.doc();
    await doc.set({
      'title': title.trim(),
      'status': ActionPlanStatus.notStarted.code,
      'sortOrder': sortOrder,
      'dueDate': null,
      'completedAt': null,
      'isComplete': false,
    });
    await _syncLegacyGoalProgress(goalId);
    return doc.id;
  }

  Future<void> _legacySetActionPlanStatus({
    required String goalId,
    required String planId,
    required ActionPlanStatus status,
    required String actorId,
  }) async {
    final ref = _goalDoc(goalId).collection('tasks').doc(planId);
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw ApiException(404, 'Task not found.');
    }
    await ref.set({
      ...snapshot.data()!,
      'status': status.code,
      'isComplete': status == ActionPlanStatus.done,
      'completedAt': status == ActionPlanStatus.done
          ? DateTime.now().toIso8601String()
          : null,
    });
    await _syncLegacyGoalProgress(goalId);
  }

  Future<void> _legacyDeleteActionPlan({
    required String goalId,
    required String planId,
    required String actorId,
  }) async {
    await _goalDoc(goalId).collection('tasks').doc(planId).delete();
    await _syncLegacyGoalProgress(goalId);
  }

  Future<void> _legacyAddComment({
    required String goalId,
    required String authorId,
    required String body,
    required bool isPrivate,
  }) async {
    await _goalDoc(goalId).collection('comments').add({
      'authorId': authorId,
      'body': body.trim(),
      'isPrivate': isPrivate,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _legacyLogMeritTarget({
    required String goalId,
    required String actorId,
  }) async {
    final ref = _goalDoc(goalId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) {
      throw ApiException(404, 'Goal not found.');
    }

    final goalType = GoalType.fromCode(data['goalType']?.toString());
    if (goalType != GoalType.merit) {
      throw StateError('Target logs are only available for merit goals.');
    }
    final targetPeriod =
        TargetPeriod.fromCode(data['targetPeriod']?.toString());
    if (targetPeriod == TargetPeriod.none) {
      throw StateError('This goal does not have a recurring target.');
    }

    final targetDate =
        DateTime.tryParse(data['targetDate']?.toString() ?? '') ??
            DateTime.now();
    final currentProgress = (data['progress'] as num?)?.toInt() ?? 0;
    final currentValue = (data['currentValue'] as num?)?.toDouble() ?? 0;
    final targetValue = (data['targetValue'] as num?)?.toDouble() ?? 0;
    final bucket = _legacyPeriodBucket(
      DateTime.tryParse(data['startDate']?.toString() ?? '') ?? DateTime.now(),
      targetPeriod,
      DateTime.now(),
    );
    final lastBucket = data['lastTargetLogBucket']?.toString();
    if (bucket == lastBucket) {
      return;
    }

    final amount = perPeriodTarget(
      targetValue,
      currentValue,
      daysUntil(targetDate),
      targetPeriod.days,
    );

    final nextValue = currentValue + amount;
    final nextProgress = _calculateMeritProgress(
      status: GoalStatus.fromCode(data['status']?.toString()),
      targetValue: targetValue,
      currentValue: nextValue,
      fallback: currentProgress,
    );

    await ref.set({
      ...data,
      'currentValue': nextValue,
      'progress': nextProgress,
      'lastTargetLogBucket': bucket,
      'lastTargetLogAt': DateTime.now().toIso8601String(),
    });
    await ref.collection('merits').add({
      'date': isoDay(DateTime.now()),
      'amount': amount,
    });
  }

  Future<void> _legacyGoExtraMile({
    required String goalId,
    required String actorId,
    required double amount,
  }) async {
    if (amount <= 0) return;
    final snapshot = await _goalDoc(goalId).get();
    final data = snapshot.data();
    if (data == null) {
      throw ApiException(404, 'Goal not found.');
    }
    final goalType = GoalType.fromCode(data['goalType']?.toString());
    final currentValue = (data['currentValue'] as num?)?.toDouble() ?? 0;
    final targetValue = (data['targetValue'] as num?)?.toDouble() ?? 0;
    final nextValue = currentValue + amount;
    final nextProgress = goalType == GoalType.merit
        ? _calculateMeritProgress(
            status: GoalStatus.fromCode(data['status']?.toString()),
            targetValue: targetValue,
            currentValue: nextValue,
            fallback: (data['progress'] as num?)?.toInt() ?? 0,
          )
        : (data['progress'] as num?)?.toInt() ?? 0;
    await _goalDoc(goalId).set({
      ...data,
      'currentValue': nextValue,
      'progress': nextProgress,
    });
    await _goalDoc(goalId).collection('merits').add({
      'date': isoDay(DateTime.now()),
      'amount': amount,
      'kind': 'extra',
    });
  }

  Future<void> _legacyDeleteGoal(String goalId) async {
    final ref = _goalDoc(goalId);
    await _legacyDeleteCollection(ref.collection('tasks'));
    await _legacyDeleteCollection(ref.collection('updates'));
    await _legacyDeleteCollection(ref.collection('comments'));
    await _legacyDeleteCollection(ref.collection('merits'));
    await ref.delete();
  }

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
    final response =
        await _api.getJson('/api/goals/$goalId/tasks', token: _token);
    final raw = response['tasks'];
    if (raw is! List) return const <ActionPlanItem>[];
    return raw
        .whereType<Map>()
        .map((task) => ActionPlanItem.fromJson(Map<String, dynamic>.from(task)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<List<GoalUpdateEntry>> _fetchUpdates(String goalId) async {
    final response =
        await _api.getJson('/api/goals/$goalId/updates', token: _token);
    final raw = response['updates'];
    if (raw is! List) return const <GoalUpdateEntry>[];
    return raw
        .whereType<Map>()
        .map(
            (item) => GoalUpdateEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<GoalCommentItem>> _fetchComments(String goalId) async {
    final response =
        await _api.getJson('/api/goals/$goalId/comments', token: _token);
    final raw = response['comments'];
    if (raw is! List) return const <GoalCommentItem>[];
    return raw
        .whereType<Map>()
        .map(
            (item) => GoalCommentItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<MeritLogItem>> _fetchMerits(String goalId) async {
    final response =
        await _api.getJson('/api/goals/$goalId/merits', token: _token);
    final raw = response['merits'];
    if (raw is! List) return const <MeritLogItem>[];
    return raw
        .whereType<Map>()
        .map((item) => MeritLogItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Stream<List<GoalSummary>> watchGoals(String uid) => _usesLegacyFirestore
      ? _legacyWatchGoals(uid)
      : _poll(() => _fetchGoals(uid), fallback: const <GoalSummary>[]);

  Stream<GoalSummary?> watchGoal(String goalId) => _usesLegacyFirestore
      ? _legacyWatchGoal(goalId)
      : _poll(() => _fetchGoal(goalId), fallback: null);

  Stream<List<ActionPlanItem>> watchPlans(String goalId) => _usesLegacyFirestore
      ? _legacyWatchPlans(goalId)
      : _poll(() => _fetchPlans(goalId), fallback: const <ActionPlanItem>[]);

  Stream<List<GoalUpdateEntry>> watchUpdates(String goalId) =>
      _usesLegacyFirestore
          ? _legacyWatchUpdates(goalId)
          : _poll(() => _fetchUpdates(goalId),
              fallback: const <GoalUpdateEntry>[]);

  Stream<List<GoalCommentItem>> watchComments(
          String goalId) =>
      _usesLegacyFirestore
          ? _legacyWatchComments(goalId)
          : _poll(() => _fetchComments(goalId),
              fallback: const <GoalCommentItem>[]);

  Stream<List<MeritLogItem>> watchMerits(String goalId) => _usesLegacyFirestore
      ? _legacyWatchMerits(goalId)
      : _poll(() => _fetchMerits(goalId), fallback: const <MeritLogItem>[]);

  Future<String> createGoal({
    required String uid,
    required GoalCategory category,
    required String title,
    String? description,
    String? notes,
    DateTime? startDate,
    required DateTime targetDate,
    GoalType goalType = GoalType.merit,
    GoalDirection direction = GoalDirection.gain,
    double targetValue = 0,
    double currentValue = 0,
    String unit = '',
    TargetPeriod targetPeriod = TargetPeriod.none,
    List<String> planTitles = const [],
  }) async {
    if (_usesLegacyFirestore) {
      return _legacyCreateGoal(
        uid: uid,
        category: category,
        title: title,
        description: description,
        notes: notes,
        startDate: startDate,
        targetDate: targetDate,
        goalType: goalType,
        direction: direction,
        targetValue: targetValue,
        currentValue: currentValue,
        unit: unit,
        targetPeriod: targetPeriod,
        planTitles: planTitles,
      );
    }

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
        'start_date': isoDay(startDate ?? DateTime.now()),
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
    DateTime? startDate,
    DateTime? targetDate,
    GoalDirection? direction,
    double? targetValue,
    double? currentValue,
    String? unit,
    GoalType? goalType,
    TargetPeriod? targetPeriod,
  }) async {
    if (_usesLegacyFirestore) {
      await _legacyUpdateGoal(
        goalId: goalId,
        actorId: actorId,
        title: title,
        description: description,
        notes: notes,
        status: status,
        startDate: startDate,
        targetDate: targetDate,
        direction: direction,
        targetValue: targetValue,
        currentValue: currentValue,
        unit: unit,
        goalType: goalType,
        targetPeriod: targetPeriod,
      );
      return;
    }

    final payload = <String, dynamic>{
      if (title != null) 'title': title.trim(),
      if (description != null || notes != null) 'description': description,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status.code,
      if (startDate != null) 'start_date': isoDay(startDate),
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
    if (_usesLegacyFirestore) {
      await _legacySetGoalMeasure(
        goalId: goalId,
        actorId: actorId,
        currentValue: currentValue,
      );
      return;
    }

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
    if (_usesLegacyFirestore) {
      return _legacyAddActionPlan(
        goalId: goalId,
        title: title,
        actorId: actorId,
      );
    }

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
    if (_usesLegacyFirestore) {
      await _legacySetActionPlanStatus(
        goalId: goalId,
        planId: planId,
        status: status,
        actorId: actorId,
      );
      return;
    }

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
    if (_usesLegacyFirestore) {
      await _legacyDeleteActionPlan(
        goalId: goalId,
        planId: planId,
        actorId: actorId,
      );
      return;
    }

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
    if (_usesLegacyFirestore) {
      await _legacyAddComment(
        goalId: goalId,
        authorId: authorId,
        body: body,
        isPrivate: isPrivate,
      );
      return;
    }

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
    if (_usesLegacyFirestore) {
      await _legacyLogMeritTarget(goalId: goalId, actorId: actorId);
      return;
    }

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
    if (_usesLegacyFirestore) {
      await _legacyGoExtraMile(
        goalId: goalId,
        actorId: actorId,
        amount: amount,
      );
      return;
    }

    await _api.postJson(
      '/api/goals/$goalId/merits/extra',
      {'amount': amount},
      token: _token,
    );
  }

  Future<void> deleteGoal(String goalId) async {
    if (_usesLegacyFirestore) {
      await _legacyDeleteGoal(goalId);
      return;
    }

    await _api.deleteJson(
      '/api/goals/$goalId',
      token: _token,
    );
  }
}
