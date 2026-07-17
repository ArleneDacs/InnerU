/// Firestore access for the Goals feature — a port of A12-Tracker's
/// `src/server/goals.ts` write rules onto Firestore. Screens never touch
/// Firestore directly; they go through this service. The Firestore instance
/// is injected so tests can pass a FakeFirebaseFirestore.
library;

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/day_keys.dart';
import '../domain/domain.dart';
import '../domain/scoring.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

DateTime? _asDate(Object? v) => v is Timestamp ? v.toDate() : null;

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

  factory GoalSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalSummary(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      companyId: (data['companyId'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: data['description'] as String?,
      notes: data['notes'] as String?,
      status: GoalStatus.fromCode(data['status'] as String?),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      category: GoalCategory.fromCode(data['category'] as String?),
      goalType: GoalType.fromCode(data['goalType'] as String?),
      targetPeriod: TargetPeriod.fromCode(data['targetPeriod'] as String?),
      direction: GoalDirection.fromCode(data['direction'] as String?),
      targetValue: (data['targetValue'] as num?)?.toDouble() ?? 0,
      currentValue: (data['currentValue'] as num?)?.toDouble() ?? 0,
      unit: (data['unit'] as String?) ?? '',
      startDate: _asDate(data['startDate']) ?? DateTime.now(),
      targetDate: _asDate(data['targetDate']) ?? DateTime.now(),
      completedAt: _asDate(data['completedAt']),
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

  /// Scored by the same engine that will rank leaderboards. For MILESTONE
  /// goals the stored progress already mirrors plan completion, so the
  /// summary needs no subcollection read.
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

  /// A periodic MERIT goal's per-period target; 0 otherwise.
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

  factory ActionPlanItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ActionPlanItem(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      status: ActionPlanStatus.fromCode(data['status'] as String?),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      dueDate: _asDate(data['dueDate']),
      completedAt: _asDate(data['completedAt']),
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

  factory GoalUpdateEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalUpdateEntry(
      id: doc.id,
      authorId: (data['authorId'] as String?) ?? '',
      progressFrom: (data['progressFrom'] as num?)?.toInt() ?? 0,
      progressTo: (data['progressTo'] as num?)?.toInt() ?? 0,
      statusFrom: GoalStatus.fromCode(data['statusFrom'] as String?),
      statusTo: GoalStatus.fromCode(data['statusTo'] as String?),
      note: data['note'] as String?,
      createdAt: _asDate(data['createdAt']),
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

  factory GoalCommentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalCommentItem(
      id: doc.id,
      authorId: (data['authorId'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      isPrivate: data['isPrivate'] == true,
      createdAt: _asDate(data['createdAt']),
    );
  }

  final String id;
  final String authorId;
  final String body;

  /// Private = visible to coaches only (enforced when coach views arrive
  /// in Phase 4; mentees always see their own goals' comments).
  final bool isPrivate;
  final DateTime? createdAt;
}

class MeritLogItem {
  const MeritLogItem({required this.id, required this.date, required this.amount});

  factory MeritLogItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MeritLogItem(
      id: doc.id,
      date: (data['date'] as String?) ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;

  /// isoDay string of the day the merit was logged.
  final String date;
  final double amount;
}

/// The required categories a user has no live goal in. Abandoned goals do
/// not hold a category.
List<GoalCategory> requiredGoalGaps(List<GoalSummary> goals) {
  final held = goals
      .where((g) => g.status != GoalStatus.abandoned)
      .map((g) => g.category)
      .toSet();
  return GoalCategory.values.where((c) => !held.contains(c)).toList();
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class GoalsService {
  GoalsService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _goals =>
      _firestore.collection('goals');

  /// The stored `progress` mirror must use the same rule `scoreGoal` does,
  /// or the bar and the score would disagree.
  int _measurePct(double targetValue, double currentValue, int fallback) {
    if (targetValue > 0) {
      return ((currentValue / targetValue) * 100).round().clamp(0, 100);
    }
    return fallback.clamp(0, 100);
  }

  /// Informational for MERIT, the score itself for MILESTONE.
  int _planCompletionOf(Iterable<ActionPlanStatus> statuses) {
    final list = statuses.toList();
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, s) => acc + s.weight);
    return (sum / list.length).round();
  }

  Future<String> _activeCompanyId(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    return (data['activeCompanyId'] as String?) ??
        (data['companyId'] as String?) ??
        '';
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Stream<List<GoalSummary>> watchGoals(String uid) => _goals
          .where('userId', isEqualTo: uid)
          .snapshots()
          .map((snapshot) {
        final goals = snapshot.docs.map(GoalSummary.fromDoc).toList()
          ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
        return goals;
      });

  Stream<GoalSummary?> watchGoal(String goalId) => _goals
      .doc(goalId)
      .snapshots()
      .map((doc) => doc.exists ? GoalSummary.fromDoc(doc) : null);

  Stream<List<ActionPlanItem>> watchPlans(String goalId) => _goals
          .doc(goalId)
          .collection('tasks')
          .snapshots()
          .map((snapshot) {
        final plans = snapshot.docs.map(ActionPlanItem.fromDoc).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return plans;
      });

  Stream<List<GoalUpdateEntry>> watchUpdates(String goalId) => _goals
      .doc(goalId)
      .collection('updates')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(GoalUpdateEntry.fromDoc).toList());

  Stream<List<GoalCommentItem>> watchComments(String goalId) => _goals
      .doc(goalId)
      .collection('comments')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(GoalCommentItem.fromDoc).toList());

  Stream<List<MeritLogItem>> watchMerits(String goalId) => _goals
      .doc(goalId)
      .collection('merits')
      .orderBy('date', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(MeritLogItem.fromDoc).toList());

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

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
    final companyId = await _activeCompanyId(uid);

    // A milestone goal has no numeric measure — its plans are the score.
    final isMilestone = goalType == GoalType.milestone;
    final tv = isMilestone ? 0.0 : math.max(0.0, targetValue);
    final cv = isMilestone ? 0.0 : math.max(0.0, currentValue);

    final doc = _goals.doc();
    final batch = _firestore.batch();
    batch.set(doc, {
      'userId': uid,
      'companyId': companyId,
      'category': category.code,
      'title': title,
      'description': description,
      'notes': notes,
      'status': GoalStatus.notStarted.code,
      'goalType': goalType.code,
      'direction': (isMilestone ? GoalDirection.gain : direction).code,
      'targetValue': tv,
      'currentValue': cv,
      'unit': isMilestone ? '' : unit.trim(),
      'targetPeriod':
          (isMilestone ? TargetPeriod.none : targetPeriod).code,
      'startDate': Timestamp.fromDate(dayKey(DateTime.now())),
      'targetDate': Timestamp.fromDate(dayKey(targetDate)),
      'completedAt': null,
      'progress': isMilestone ? 0 : _measurePct(tv, cv, 0),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final titles = planTitles
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i < titles.length; i++) {
      batch.set(doc.collection('tasks').doc(), {
        'title': titles[i],
        'status': ActionPlanStatus.notStarted.code,
        'isComplete': false,
        'dueDate': null,
        'completedAt': null,
        'sortOrder': i,
        'weight': 1,
      });
    }

    await batch.commit();
    return doc.id;
  }

  Future<Map<String, dynamic>> _loadGoalOrThrow(String goalId) async {
    final doc = await _goals.doc(goalId).get();
    final data = doc.data();
    if (data == null) {
      throw StateError('That goal no longer exists.');
    }
    return data;
  }

  /// Appends a ledger `set` to [batch] so the goal-doc update and its ledger
  /// row commit atomically — a crash between two separate awaits would
  /// otherwise break the "mirrored write always has a ledger row" guarantee.
  void _addLedgerEntryTo(
    WriteBatch batch,
    String goalId, {
    required String authorId,
    required int progressFrom,
    required int progressTo,
    required GoalStatus statusFrom,
    required GoalStatus statusTo,
    String? note,
  }) {
    batch.set(_goals.doc(goalId).collection('updates').doc(), {
      'authorId': authorId,
      'progressFrom': progressFrom,
      'progressTo': progressTo,
      'statusFrom': statusFrom.code,
      'statusTo': statusTo.code,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
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
    final goal = await _loadGoalOrThrow(goalId);

    final statusFrom = GoalStatus.fromCode(goal['status'] as String?);
    final statusTo = status ?? statusFrom;
    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;

    final type = goalType ?? GoalType.fromCode(goal['goalType'] as String?);
    final isMilestone = type == GoalType.milestone;
    final period = isMilestone
        ? TargetPeriod.none
        : (targetPeriod ??
            TargetPeriod.fromCode(goal['targetPeriod'] as String?));
    final tv = isMilestone
        ? 0.0
        : (targetValue != null
            ? math.max(0.0, targetValue)
            : (goal['targetValue'] as num?)?.toDouble() ?? 0);
    final cv = isMilestone
        ? 0.0
        : (currentValue != null
            ? math.max(0.0, currentValue)
            : (goal['currentValue'] as num?)?.toDouble() ?? 0);

    // Progress mirrors the score: the measure for MERIT, plan completion
    // for MILESTONE, pinned to 100 when the goal is marked complete.
    final completing =
        statusTo == GoalStatus.completed && statusFrom != GoalStatus.completed;
    final reopening =
        statusFrom == GoalStatus.completed && statusTo != GoalStatus.completed;
    int progressTo;
    if (statusTo == GoalStatus.completed) {
      progressTo = 100;
    } else if (isMilestone) {
      final plans = await _goals.doc(goalId).collection('tasks').get();
      progressTo = _planCompletionOf(plans.docs
          .map((d) => ActionPlanStatus.fromCode(d.data()['status'] as String?)));
    } else {
      progressTo = _measurePct(tv, cv, progressFrom);
    }

    final batch = _firestore.batch();
    batch.update(_goals.doc(goalId), {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (notes != null) 'notes': notes,
      if (targetDate != null) 'targetDate': Timestamp.fromDate(dayKey(targetDate)),
      if (direction != null && !isMilestone) 'direction': direction.code,
      if (unit != null && !isMilestone) 'unit': unit.trim(),
      'goalType': type.code,
      'targetPeriod': period.code,
      'targetValue': tv,
      'currentValue': cv,
      'status': statusTo.code,
      'progress': progressTo,
      if (completing) 'completedAt': Timestamp.fromDate(DateTime.now()),
      if (reopening) 'completedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addLedgerEntryTo(
      batch,
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusFrom,
      statusTo: statusTo,
    );
    await batch.commit();
  }

  /// Updates just the "current" measure value and re-mirrors the bar.
  Future<void> setGoalMeasure({
    required String goalId,
    required String actorId,
    required double currentValue,
  }) async {
    final goal = await _loadGoalOrThrow(goalId);
    if (GoalType.fromCode(goal['goalType'] as String?) != GoalType.merit) {
      throw StateError('Only a merit goal has a measure to set.');
    }
    final statusFrom = GoalStatus.fromCode(goal['status'] as String?);
    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;
    final current = math.max(0.0, currentValue);
    final progressTo = statusFrom == GoalStatus.completed
        ? 100
        : _measurePct(
            (goal['targetValue'] as num?)?.toDouble() ?? 0,
            current,
            progressFrom,
          );

    final batch = _firestore.batch();
    batch.update(_goals.doc(goalId), {
      'currentValue': current,
      'progress': progressTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addLedgerEntryTo(
      batch,
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusFrom,
      statusTo: statusFrom,
    );
    await batch.commit();
  }

  Future<String> addActionPlan({
    required String goalId,
    required String title,
    required String actorId,
  }) async {
    final existing = await _goals.doc(goalId).collection('tasks').get();
    final doc = await _goals.doc(goalId).collection('tasks').add({
      'title': title.trim(),
      'status': ActionPlanStatus.notStarted.code,
      'isComplete': false,
      'dueDate': null,
      'completedAt': null,
      'sortOrder': existing.docs.length,
      'weight': 1,
    });
    await _mirrorMilestoneProgress(goalId, actorId);
    return doc.id;
  }

  /// Re-mirrors a MILESTONE goal's progress after any plan change, unless
  /// the goal is COMPLETED (pinned at 100).
  Future<void> _mirrorMilestoneProgress(String goalId, String actorId) async {
    final goal = await _loadGoalOrThrow(goalId);
    if (GoalType.fromCode(goal['goalType'] as String?) != GoalType.milestone) {
      return;
    }
    final statusNow = GoalStatus.fromCode(goal['status'] as String?);
    if (statusNow == GoalStatus.completed) return;

    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;
    final plans = await _goals.doc(goalId).collection('tasks').get();
    final progressTo = _planCompletionOf(plans.docs
        .map((d) => ActionPlanStatus.fromCode(d.data()['status'] as String?)));
    if (progressTo == progressFrom) return;

    final batch = _firestore.batch();
    batch.update(_goals.doc(goalId), {
      'progress': progressTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addLedgerEntryTo(
      batch,
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusNow,
      statusTo: statusNow,
    );
    await batch.commit();
  }

  Future<void> setActionPlanStatus({
    required String goalId,
    required String planId,
    required ActionPlanStatus status,
    required String actorId,
  }) async {
    await _goals.doc(goalId).collection('tasks').doc(planId).update({
      'status': status.code,
      'isComplete': status == ActionPlanStatus.done,
      'completedAt': status == ActionPlanStatus.done
          ? Timestamp.fromDate(DateTime.now())
          : null,
    });
    await _mirrorMilestoneProgress(goalId, actorId);
  }

  Future<void> deleteActionPlan({
    required String goalId,
    required String planId,
    required String actorId,
  }) async {
    await _goals.doc(goalId).collection('tasks').doc(planId).delete();
    await _mirrorMilestoneProgress(goalId, actorId);
  }

  Future<void> addComment({
    required String goalId,
    required String authorId,
    required String body,
    bool isPrivate = false,
  }) {
    return _goals.doc(goalId).collection('comments').add({
      'authorId': authorId,
      'body': body.trim(),
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGoal(String goalId) async {
    // Firestore does not cascade-delete subcollections; sweep them first.
    for (final sub in ['tasks', 'updates', 'comments', 'merits']) {
      final docs = await _goals.doc(goalId).collection(sub).get();
      for (final doc in docs.docs) {
        await doc.reference.delete();
      }
    }
    await _goals.doc(goalId).delete();
  }
}
