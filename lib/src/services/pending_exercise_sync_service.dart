import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/exercise_api_service.dart';
import 'package:selfcare_projects/src/services/exercise_local_photo_store.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExerciseCaptureSlot { start, end }

extension ExerciseCaptureSlotX on ExerciseCaptureSlot {
  String get storageValue => name;
}

/// Session data persisted before a timer is allowed to run. When a member
/// dismisses the camera, [startPhotoReference] remains null so the existing
/// optional-photo exercise flow stays usable offline.
class ExerciseLocalSession {
  const ExerciseLocalSession({
    required this.clientSessionId,
    required this.userId,
    required this.type,
    required this.goalDurationSeconds,
    required this.intensity,
    required this.notes,
    required this.startedAt,
    this.startPhotoReference,
    this.stoppedDurationSeconds,
    this.stoppedAt,
    this.pendingEndPhotoReference,
  });

  final String clientSessionId;
  final String userId;
  final String type;
  final int goalDurationSeconds;
  final int intensity;
  final String notes;
  final DateTime startedAt;
  final String? startPhotoReference;

  /// The elapsed duration is frozen as soon as Stop is tapped. Keeping it in
  /// the durable session means a retry after a camera cancellation or app
  /// restart never records extra time.
  final int? stoppedDurationSeconds;

  /// Exact Stop-tap time. This preserves the intended log date and interval
  /// if a member retries after a camera interruption or app restart.
  final DateTime? stoppedAt;

  /// An end photo can be captured before the completed record is enqueued.
  /// Retain that local reference if the very small local queue write fails.
  final String? pendingEndPhotoReference;

  ExerciseLocalSession copyWith({
    int? stoppedDurationSeconds,
    String? pendingEndPhotoReference,
    bool clearPendingEndPhotoReference = false,
  }) {
    return ExerciseLocalSession(
      clientSessionId: clientSessionId,
      userId: userId,
      type: type,
      goalDurationSeconds: goalDurationSeconds,
      intensity: intensity,
      notes: notes,
      startedAt: startedAt,
      startPhotoReference: startPhotoReference,
      stoppedDurationSeconds:
          stoppedDurationSeconds ?? this.stoppedDurationSeconds,
      stoppedAt: stoppedAt,
      pendingEndPhotoReference: clearPendingEndPhotoReference
          ? null
          : pendingEndPhotoReference ?? this.pendingEndPhotoReference,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientSessionId': clientSessionId,
        'userId': userId,
        'type': type,
        'goalDurationSeconds': goalDurationSeconds,
        'intensity': intensity,
        'notes': notes,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        if (startPhotoReference != null && startPhotoReference!.isNotEmpty)
          'startPhotoReference': startPhotoReference,
        if (stoppedDurationSeconds != null)
          'stoppedDurationSeconds': stoppedDurationSeconds,
        if (stoppedAt != null) 'stoppedAtMs': stoppedAt!.millisecondsSinceEpoch,
        if (pendingEndPhotoReference != null &&
            pendingEndPhotoReference!.isNotEmpty)
          'pendingEndPhotoReference': pendingEndPhotoReference,
      };

  factory ExerciseLocalSession.fromJson(Map<String, dynamic> json) {
    return ExerciseLocalSession(
      clientSessionId: _nonEmptyString(json['clientSessionId']),
      userId: _nonEmptyString(json['userId']),
      type: _nonEmptyString(json['type'], fallback: 'Exercise'),
      goalDurationSeconds: _readInt(json['goalDurationSeconds']),
      intensity: _readInt(json['intensity'], fallback: 2),
      notes: json['notes']?.toString() ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(json['startedAtMs']),
      ),
      startPhotoReference: _nullableString(json['startPhotoReference']),
      stoppedDurationSeconds: _nullableInt(json['stoppedDurationSeconds']),
      stoppedAt: _nullableInt(json['stoppedAtMs']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_readInt(json['stoppedAtMs'])),
      pendingEndPhotoReference:
          _nullableString(json['pendingEndPhotoReference']),
    );
  }
}

/// Records which camera slot was open if Android kills the app while ImagePicker
/// owns the activity. [retrieveLostData] can safely finish this intent later.
class ExerciseCaptureIntent {
  const ExerciseCaptureIntent({
    required this.userId,
    required this.clientSessionId,
    required this.slot,
    required this.type,
    required this.goalDurationSeconds,
    required this.intensity,
    required this.notes,
    this.startedAt,
    this.endedAt,
    this.startPhotoReference,
  });

  final String userId;
  final String clientSessionId;
  final ExerciseCaptureSlot slot;
  final String type;
  final int goalDurationSeconds;
  final int intensity;
  final String notes;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? startPhotoReference;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'userId': userId,
        'clientSessionId': clientSessionId,
        'slot': slot.storageValue,
        'type': type,
        'goalDurationSeconds': goalDurationSeconds,
        'intensity': intensity,
        'notes': notes,
        if (startedAt != null) 'startedAtMs': startedAt!.millisecondsSinceEpoch,
        if (endedAt != null) 'endedAtMs': endedAt!.millisecondsSinceEpoch,
        if (startPhotoReference != null && startPhotoReference!.isNotEmpty)
          'startPhotoReference': startPhotoReference,
      };

  factory ExerciseCaptureIntent.fromJson(Map<String, dynamic> json) {
    final slotValue = json['slot']?.toString();
    return ExerciseCaptureIntent(
      userId: _nonEmptyString(json['userId']),
      clientSessionId: _nonEmptyString(json['clientSessionId']),
      slot: slotValue == ExerciseCaptureSlot.end.storageValue
          ? ExerciseCaptureSlot.end
          : ExerciseCaptureSlot.start,
      type: _nonEmptyString(json['type'], fallback: 'Exercise'),
      goalDurationSeconds: _readInt(json['goalDurationSeconds']),
      intensity: _readInt(json['intensity'], fallback: 2),
      notes: json['notes']?.toString() ?? '',
      startedAt: _nullableInt(json['startedAtMs']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_readInt(json['startedAtMs'])),
      endedAt: _nullableInt(json['endedAtMs']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_readInt(json['endedAtMs'])),
      startPhotoReference: _nullableString(json['startPhotoReference']),
    );
  }
}

/// A completed, locally durable exercise record awaiting remote upload.
///
/// `remoteSavedAtMs` and `streakProcessedAtMs` are checkpoints. They prevent
/// a later retry from uploading an already accepted record or reprocessing its
/// reward state after an app kill between those two steps.
class PendingExerciseRecord {
  factory PendingExerciseRecord({
    required String clientSessionId,
    required String userId,
    required String type,
    required int durationSeconds,
    required int intensity,
    required String notes,
    required DateTime startedAt,
    required DateTime endedAt,
    String? startPhotoReference,
    String? endPhotoReference,
    int? remoteSavedAtMs,
    int? streakProcessedAtMs,
    String? lastSyncError,
  }) {
    final boundedDuration = boundedExerciseLogDuration(
      Duration(seconds: durationSeconds),
    );
    // A forgotten session can span days. The API derives the authoritative
    // duration from timestamps, so carrying the original start with a capped
    // duration would still make the record unsaveable. Keep the end moment
    // (and therefore its local calendar date), then derive a valid start.
    final rawInterval = endedAt.difference(startedAt);
    final effectiveStartedAt =
        rawInterval <= Duration.zero || rawInterval > maximumExerciseLogDuration
            ? endedAt.subtract(boundedDuration)
            : startedAt;
    return PendingExerciseRecord._(
      clientSessionId: clientSessionId,
      userId: userId,
      type: type,
      durationSeconds: boundedDuration.inSeconds,
      intensity: intensity.clamp(1, 3).toInt(),
      notes: notes,
      startedAt: effectiveStartedAt,
      endedAt: endedAt,
      startPhotoReference: startPhotoReference,
      endPhotoReference: endPhotoReference,
      remoteSavedAtMs: remoteSavedAtMs,
      streakProcessedAtMs: streakProcessedAtMs,
      lastSyncError: lastSyncError,
    );
  }

  const PendingExerciseRecord._({
    required this.clientSessionId,
    required this.userId,
    required this.type,
    required this.durationSeconds,
    required this.intensity,
    required this.notes,
    required this.startedAt,
    required this.endedAt,
    required this.startPhotoReference,
    required this.endPhotoReference,
    this.remoteSavedAtMs,
    this.streakProcessedAtMs,
    this.lastSyncError,
  });

  final String clientSessionId;
  final String userId;
  final String type;
  final int durationSeconds;
  final int intensity;
  final String notes;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? startPhotoReference;
  final String? endPhotoReference;
  final int? remoteSavedAtMs;
  final int? streakProcessedAtMs;
  final String? lastSyncError;

  int get durationMinutes =>
      exerciseLogDurationMinutes(Duration(seconds: durationSeconds));

  String get date => _dateKey(endedAt);

  bool get isRemoteSaved => remoteSavedAtMs != null;

  bool get isStreakProcessed => streakProcessedAtMs != null;

  PendingExerciseRecord copyWith({
    int? remoteSavedAtMs,
    int? streakProcessedAtMs,
    String? lastSyncError,
    bool clearLastSyncError = false,
  }) {
    return PendingExerciseRecord(
      clientSessionId: clientSessionId,
      userId: userId,
      type: type,
      durationSeconds: durationSeconds,
      intensity: intensity,
      notes: notes,
      startedAt: startedAt,
      endedAt: endedAt,
      startPhotoReference: startPhotoReference,
      endPhotoReference: endPhotoReference,
      remoteSavedAtMs: remoteSavedAtMs ?? this.remoteSavedAtMs,
      streakProcessedAtMs: streakProcessedAtMs ?? this.streakProcessedAtMs,
      lastSyncError:
          clearLastSyncError ? null : lastSyncError ?? this.lastSyncError,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientSessionId': clientSessionId,
        'userId': userId,
        'type': type,
        'durationSeconds': durationSeconds,
        'intensity': intensity,
        'notes': notes,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'endedAtMs': endedAt.millisecondsSinceEpoch,
        if (startPhotoReference != null && startPhotoReference!.isNotEmpty)
          'startPhotoReference': startPhotoReference,
        if (endPhotoReference != null && endPhotoReference!.isNotEmpty)
          'endPhotoReference': endPhotoReference,
        if (remoteSavedAtMs != null) 'remoteSavedAtMs': remoteSavedAtMs,
        if (streakProcessedAtMs != null)
          'streakProcessedAtMs': streakProcessedAtMs,
        if (lastSyncError != null && lastSyncError!.isNotEmpty)
          'lastSyncError': lastSyncError,
      };

  factory PendingExerciseRecord.fromJson(Map<String, dynamic> json) {
    return PendingExerciseRecord(
      clientSessionId: _nonEmptyString(json['clientSessionId']),
      userId: _nonEmptyString(json['userId']),
      type: _nonEmptyString(json['type'], fallback: 'Exercise'),
      durationSeconds: boundedExerciseLogDuration(
        Duration(seconds: _readInt(json['durationSeconds'])),
      ).inSeconds,
      intensity: _readInt(json['intensity'], fallback: 2),
      notes: json['notes']?.toString() ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(json['startedAtMs']),
      ),
      endedAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(json['endedAtMs']),
      ),
      startPhotoReference: _nullableString(json['startPhotoReference']),
      endPhotoReference: _nullableString(json['endPhotoReference']),
      remoteSavedAtMs: _nullableInt(json['remoteSavedAtMs']),
      streakProcessedAtMs: _nullableInt(json['streakProcessedAtMs']),
      lastSyncError: _nullableString(json['lastSyncError']),
    );
  }
}

enum ExerciseSyncPhase {
  idle,
  savingLocally,
  pendingSync,
  syncing,
  synced,
}

class ExerciseSyncStatus {
  const ExerciseSyncStatus({
    required this.phase,
    this.userId,
    this.clientSessionId,
    this.error,
    this.unlockedMilestones = const <ActivityStreakMilestone>[],
  });

  const ExerciseSyncStatus.idle() : this(phase: ExerciseSyncPhase.idle);

  final ExerciseSyncPhase phase;
  final String? userId;
  final String? clientSessionId;
  final String? error;
  final List<ActivityStreakMilestone> unlockedMilestones;
}

abstract class ExerciseSyncGateway {
  Future<String?> uploadPhoto(
    Uint8List bytes, {
    required String fileName,
  });

  Future<void> saveRecord(
    PendingExerciseRecord record, {
    String? startPhotoUrl,
    String? endPhotoUrl,
  });
}

class _DefaultExerciseSyncGateway implements ExerciseSyncGateway {
  _DefaultExerciseSyncGateway(this._api);

  final ExerciseApiService _api;

  @override
  Future<String?> uploadPhoto(
    Uint8List bytes, {
    required String fileName,
  }) {
    return ImageStorageService.uploadExerciseImageBytes(
      bytes,
      fileName: fileName,
    );
  }

  @override
  Future<void> saveRecord(
    PendingExerciseRecord record, {
    String? startPhotoUrl,
    String? endPhotoUrl,
  }) async {
    await _api.store(
      type: record.type,
      durationMinutes: record.durationMinutes,
      durationSeconds: record.durationSeconds,
      intensity: record.intensity,
      notes: record.notes,
      startPhotoUrl: startPhotoUrl,
      endPhotoUrl: endPhotoUrl,
      clientSessionId: record.clientSessionId,
      startedAt: record.startedAt,
      endedAt: record.endedAt,
    );
  }
}

typedef ExercisePreferencesLoader = Future<SharedPreferences> Function();

/// Returns an opaque value that changes when the signed-in account or its
/// credentials change. It is injectable so queue behavior can be verified
/// without relying on the process-wide authentication singleton.
typedef ExerciseSyncOwnerTokenProvider = String? Function(String userId);

typedef ExerciseStreakProcessor = Future<List<ActivityStreakMilestone>>
    Function(PendingExerciseRecord record);

String? _defaultOwnerTokenFor(String userId) {
  final session = AuthService.instance.currentSession;
  if (session == null || session.id.toString() != userId) return null;
  return session.token;
}

/// A durable, local-first exercise completion queue.
///
/// Camera bytes are written before a completed record joins this queue. The
/// queue is scoped to one member, protected against overlapping flushes, and
/// only deletes a record after both its remote log and local streak update are
/// confirmed. A retry therefore never blocks the Start/Stop controls.
class PendingExerciseSyncService {
  PendingExerciseSyncService({
    ExerciseLocalPhotoStore? photoStore,
    ExerciseSyncGateway? gateway,
    ActivityStreakService? activityStreakService,
    ExercisePreferencesLoader? preferencesLoader,
    ExerciseSyncOwnerTokenProvider? ownerTokenProvider,
    ExerciseStreakProcessor? streakProcessor,
    Duration networkTimeout = const Duration(seconds: 20),
  })  : _photoStore = photoStore ?? createExerciseLocalPhotoStore(),
        _gateway =
            gateway ?? _DefaultExerciseSyncGateway(ExerciseApiService.instance),
        _activityStreakService =
            activityStreakService ?? ActivityStreakService(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _ownerTokenProvider = ownerTokenProvider ?? _defaultOwnerTokenFor,
        _streakProcessor = streakProcessor,
        _networkTimeout = networkTimeout;

  static final PendingExerciseSyncService instance =
      PendingExerciseSyncService();

  static const _activeSessionKey = 'exercise_local_active_session_v2';
  static const _captureIntentKey = 'exercise_local_capture_intent_v2';
  static const _queuePrefix = 'pending_exercise_syncs_v2_';

  final ExerciseLocalPhotoStore _photoStore;
  final ExerciseSyncGateway _gateway;
  final ActivityStreakService _activityStreakService;
  final ExercisePreferencesLoader _preferencesLoader;
  final ExerciseSyncOwnerTokenProvider _ownerTokenProvider;
  final ExerciseStreakProcessor? _streakProcessor;
  final Duration _networkTimeout;
  final Map<String, Future<void>> _activeFlushes = <String, Future<void>>{};
  final Map<String, Future<void>> _queueOperationTails =
      <String, Future<void>>{};
  final Map<String, int> _userGenerations = <String, int>{};

  final ValueNotifier<ExerciseSyncStatus> status =
      ValueNotifier<ExerciseSyncStatus>(const ExerciseSyncStatus.idle());

  static String queuePreferenceKey(String userId) => '$_queuePrefix$userId';

  Future<String> persistPhoto({
    required String userId,
    required String clientSessionId,
    required ExerciseCaptureSlot slot,
    required Uint8List bytes,
  }) {
    return _photoStore.save(
      userId: userId,
      clientSessionId: clientSessionId,
      slot: slot.storageValue,
      bytes: bytes,
    );
  }

  Future<Uint8List?> readPhoto(String reference) => _photoStore.read(reference);

  Future<void> saveActiveSession(ExerciseLocalSession session) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_activeSessionKey, jsonEncode(session.toJson()));
  }

  Future<ExerciseLocalSession?> loadActiveSession(String userId) async {
    if (userId.isEmpty) return null;
    final prefs = await _preferencesLoader();
    final encoded = prefs.getString(_activeSessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final session = ExerciseLocalSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return session.userId == userId ? session : null;
    } catch (error) {
      debugPrint('Invalid local exercise session: $error');
      return null;
    }
  }

  Future<void> clearActiveSession({String? userId}) async {
    final prefs = await _preferencesLoader();
    if (userId != null && userId.isNotEmpty) {
      final current = await loadActiveSession(userId);
      if (current == null) return;
    }
    await prefs.remove(_activeSessionKey);
  }

  Future<void> saveCaptureIntent(ExerciseCaptureIntent intent) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_captureIntentKey, jsonEncode(intent.toJson()));
  }

  Future<ExerciseCaptureIntent?> loadCaptureIntent(String userId) async {
    if (userId.isEmpty) return null;
    final prefs = await _preferencesLoader();
    final encoded = prefs.getString(_captureIntentKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final intent = ExerciseCaptureIntent.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return intent.userId == userId ? intent : null;
    } catch (error) {
      debugPrint('Invalid exercise camera intent: $error');
      return null;
    }
  }

  Future<void> clearCaptureIntent({String? userId}) async {
    final prefs = await _preferencesLoader();
    if (userId != null && userId.isNotEmpty) {
      final intent = await loadCaptureIntent(userId);
      if (intent == null) return;
    }
    await prefs.remove(_captureIntentKey);
  }

  Future<void> queueCompleted(PendingExerciseRecord record) async {
    if (record.userId.isEmpty || record.clientSessionId.isEmpty) {
      throw ArgumentError('A queued exercise requires a user and client ID.');
    }
    _emit(
      ExerciseSyncPhase.savingLocally,
      userId: record.userId,
      clientSessionId: record.clientSessionId,
    );
    final generation = _userGenerations[record.userId] ?? 0;
    final ownerToken = _currentOwnerToken(record.userId);
    if (ownerToken == null) {
      throw StateError('Exercise completion belongs to a signed-out account.');
    }
    await _withQueueLock(record.userId, () async {
      // A camera callback can arrive after logout/account switch. Never let
      // it recreate the just-cleared queue for the prior member.
      if ((_userGenerations[record.userId] ?? 0) != generation ||
          !_stillOwnsSession(record.userId, ownerToken)) {
        throw StateError(
            'The signed-in account changed before saving exercise.');
      }
      final prefs = await _preferencesLoader();
      final pending = await _loadQueue(prefs, record.userId);
      pending[record.clientSessionId] = record;
      await _saveQueue(prefs, record.userId, pending);
    });
    _emit(
      ExerciseSyncPhase.pendingSync,
      userId: record.userId,
      clientSessionId: record.clientSessionId,
    );
  }

  Future<List<PendingExerciseRecord>> pendingRecords(String userId) async {
    if (userId.isEmpty) return const <PendingExerciseRecord>[];
    return _withQueueLock(userId, () async {
      final prefs = await _preferencesLoader();
      final records = (await _loadQueue(prefs, userId)).values.toList()
        ..sort((a, b) => a.endedAt.compareTo(b.endedAt));
      return records;
    });
  }

  Future<void> refreshStatus(String userId) async {
    final records = await pendingRecords(userId);
    if (records.isEmpty) return;
    _emit(
      ExerciseSyncPhase.pendingSync,
      userId: userId,
      clientSessionId: records.first.clientSessionId,
      error: records.first.lastSyncError,
    );
  }

  /// Flushes one user's queue. Concurrent manual, startup, and lifecycle
  /// requests share a single Future so a record cannot upload twice in one
  /// process. Server-side [clientSessionId] idempotency protects a crash
  /// between the remote write and the local checkpoint.
  Future<void> flush({required String userId}) {
    if (userId.isEmpty) return Future<void>.value();
    final active = _activeFlushes[userId];
    if (active != null) return active;

    late final Future<void> future;
    future = _flushInternal(userId).whenComplete(() {
      if (identical(_activeFlushes[userId], future)) {
        _activeFlushes.remove(userId);
      }
    });
    _activeFlushes[userId] = future;
    return future;
  }

  Future<void> _flushInternal(String userId) async {
    final generation = _userGenerations[userId] ?? 0;
    final ownerToken = _currentOwnerToken(userId);
    if (ownerToken == null) return;

    while (true) {
      if ((_userGenerations[userId] ?? 0) != generation) return;
      if (!_stillOwnsSession(userId, ownerToken)) return;
      final records = await pendingRecords(userId);
      if (records.isEmpty) return;

      // Oldest completions first. Re-reading each iteration means a record
      // queued while another record uploads is retained and can sync during
      // this same pass rather than waiting for the periodic retry.
      final originalRecord = records.first;
      final current = originalRecord;

      try {
        var record = current;
        if (!record.isRemoteSaved) {
          _emit(
            ExerciseSyncPhase.syncing,
            userId: userId,
            clientSessionId: record.clientSessionId,
          );
          if (!_stillOwnsSession(userId, ownerToken)) return;
          final startPhotoUrl = await _uploadReference(
            record.startPhotoReference,
            userId: userId,
            ownerToken: ownerToken,
            generation: generation,
            clientSessionId: record.clientSessionId,
            slot: ExerciseCaptureSlot.start,
          );
          if (!_stillOwnsSession(userId, ownerToken)) return;
          final endPhotoUrl = await _uploadReference(
            record.endPhotoReference,
            userId: userId,
            ownerToken: ownerToken,
            generation: generation,
            clientSessionId: record.clientSessionId,
            slot: ExerciseCaptureSlot.end,
          );
          if ((_userGenerations[userId] ?? 0) != generation) return;
          if (!_stillOwnsSession(userId, ownerToken)) return;
          await _gateway
              .saveRecord(
                record,
                startPhotoUrl: startPhotoUrl,
                endPhotoUrl: endPhotoUrl,
              )
              .timeout(_networkTimeout);
          if ((_userGenerations[userId] ?? 0) != generation) return;
          if (!_stillOwnsSession(userId, ownerToken)) return;
          record = await _updateRecord(
                userId,
                record.clientSessionId,
                generation,
                (value) => value.copyWith(
                  remoteSavedAtMs: DateTime.now().millisecondsSinceEpoch,
                  clearLastSyncError: true,
                ),
              ) ??
              record;
          if ((_userGenerations[userId] ?? 0) != generation) return;
          if (!_stillOwnsSession(userId, ownerToken)) return;
        }

        if (!record.isStreakProcessed) {
          final streakProcessor = _streakProcessor;
          final milestones = streakProcessor != null
              ? await streakProcessor(record)
              : await _processStreak(record);
          if ((_userGenerations[userId] ?? 0) != generation) return;
          if (!_stillOwnsSession(userId, ownerToken)) return;
          record = await _updateRecord(
                userId,
                record.clientSessionId,
                generation,
                (value) => value.copyWith(
                  streakProcessedAtMs: DateTime.now().millisecondsSinceEpoch,
                  clearLastSyncError: true,
                ),
              ) ??
              record;
          if ((_userGenerations[userId] ?? 0) != generation) return;
          if (!_stillOwnsSession(userId, ownerToken)) return;
          final removed = await _removeRecord(
            userId,
            record.clientSessionId,
            generation,
          );
          if (!removed) continue;
          await _removeLocalPhotos(record);
          _emit(
            ExerciseSyncPhase.synced,
            userId: userId,
            clientSessionId: record.clientSessionId,
            unlockedMilestones: milestones,
          );
        } else {
          if (!_stillOwnsSession(userId, ownerToken)) return;
          final removed = await _removeRecord(
            userId,
            record.clientSessionId,
            generation,
          );
          if (!removed) continue;
          await _removeLocalPhotos(record);
          _emit(
            ExerciseSyncPhase.synced,
            userId: userId,
            clientSessionId: record.clientSessionId,
          );
        }
      } catch (error) {
        // An account transition invalidates this pass. Its queue has already
        // been cleared (or now belongs to a new session), so do not write an
        // old error/status back after the asynchronous operation returns.
        if ((_userGenerations[userId] ?? 0) != generation ||
            !_stillOwnsSession(userId, ownerToken)) {
          return;
        }
        final message = _safeErrorMessage(error);
        await _updateRecord(
          userId,
          originalRecord.clientSessionId,
          generation,
          (value) => value.copyWith(lastSyncError: message),
        );
        _emit(
          ExerciseSyncPhase.pendingSync,
          userId: userId,
          clientSessionId: originalRecord.clientSessionId,
          error: message,
        );
        // Preserve chronological streak processing: do not skip over an
        // older completion that failed to reach the server.
        return;
      }
    }
  }

  Future<String?> _uploadReference(
    String? reference, {
    required String userId,
    required String ownerToken,
    required int generation,
    required String clientSessionId,
    required ExerciseCaptureSlot slot,
  }) async {
    if (reference == null || reference.trim().isEmpty) return null;
    if (_isRemoteReference(reference)) return reference;
    final bytes = await _photoStore.read(reference);
    // Reading local storage is asynchronous. Re-check immediately before the
    // gateway obtains its live auth token, otherwise an account switch in
    // this gap could upload the previous member's image as the new member.
    if ((_userGenerations[userId] ?? 0) != generation ||
        !_stillOwnsSession(userId, ownerToken)) {
      throw StateError('The signed-in account changed during exercise sync.');
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
          'The ${slot.storageValue} photo is no longer available locally.');
    }
    final url = await _gateway
        .uploadPhoto(
          bytes,
          fileName: 'exercise_${clientSessionId}_${slot.storageValue}.jpg',
        )
        .timeout(_networkTimeout);
    if (url == null || url.trim().isEmpty) {
      throw StateError('Could not upload the ${slot.storageValue} photo.');
    }
    return url.trim();
  }

  Future<List<ActivityStreakMilestone>> _processStreak(
    PendingExerciseRecord record,
  ) async {
    final data = await UserService.getUserData();
    final rawLastDate =
        data['exerciseStreakLastDate'] ?? data['exercise_streak_last_date'];
    final lastDate = _parseDateOnly(rawLastDate?.toString());
    final completionDate = _dateOnly(record.endedAt);

    // A profile already advanced beyond this offline completion cannot be
    // safely backfilled by ActivityStreakService; doing so would reset the
    // saved streak backwards. Treat it as processed, while normal current and
    // forward chronological records still receive their medal update.
    if (lastDate != null && lastDate.isAfter(completionDate)) {
      return const <ActivityStreakMilestone>[];
    }
    if (lastDate != null && lastDate.isAtSameMomentAs(completionDate)) {
      return const <ActivityStreakMilestone>[];
    }
    return _activityStreakService.recordCompletedSession(
      userId: record.userId,
      type: ActivityStreakType.exercise,
      completedAt: record.endedAt,
    );
  }

  Future<PendingExerciseRecord?> _updateRecord(
    String userId,
    String clientSessionId,
    int generation,
    PendingExerciseRecord Function(PendingExerciseRecord value) update,
  ) async {
    return _withQueueLock(userId, () async {
      if ((_userGenerations[userId] ?? 0) != generation) return null;
      final prefs = await _preferencesLoader();
      final queue = await _loadQueue(prefs, userId);
      final current = queue[clientSessionId];
      if (current == null) return null;
      final updated = update(current);
      queue[clientSessionId] = updated;
      await _saveQueue(prefs, userId, queue);
      return updated;
    });
  }

  Future<bool> _removeRecord(
    String userId,
    String clientSessionId,
    int generation,
  ) async {
    return _withQueueLock(userId, () async {
      if ((_userGenerations[userId] ?? 0) != generation) return false;
      final prefs = await _preferencesLoader();
      final queue = await _loadQueue(prefs, userId);
      final removed = queue.remove(clientSessionId);
      if (removed == null) return false;
      await _saveQueue(prefs, userId, queue);
      return true;
    });
  }

  Future<void> _removeLocalPhotos(PendingExerciseRecord record) async {
    try {
      final start = record.startPhotoReference;
      final end = record.endPhotoReference;
      if (start != null && start.isNotEmpty && !_isRemoteReference(start)) {
        await _photoStore.remove(start);
      }
      if (end != null && end.isNotEmpty && !_isRemoteReference(end)) {
        await _photoStore.remove(end);
      }
    } catch (error) {
      // The remote log is already durable. A later sign-out cleanup removes
      // any orphaned local bytes, so photo cleanup must not recreate a queue.
      debugPrint('Could not remove synced exercise photos: $error');
    }
  }

  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) return;
    _userGenerations[userId] = (_userGenerations[userId] ?? 0) + 1;
    await _withQueueLock(userId, () async {
      final prefs = await _preferencesLoader();
      await prefs.remove(queuePreferenceKey(userId));
    });
    await clearActiveSession(userId: userId);
    await clearCaptureIntent(userId: userId);
    await _photoStore.clearForUser(userId);
    if (status.value.userId == userId) {
      status.value = const ExerciseSyncStatus.idle();
    }
  }

  Future<Map<String, PendingExerciseRecord>> _loadQueue(
    SharedPreferences prefs,
    String userId,
  ) async {
    await prefs.reload();
    final encoded = prefs.getString(queuePreferenceKey(userId));
    if (encoded == null || encoded.isEmpty) {
      return <String, PendingExerciseRecord>{};
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, PendingExerciseRecord>{};
      final records = <String, PendingExerciseRecord>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        try {
          final record = PendingExerciseRecord.fromJson(
            Map<String, dynamic>.from(value),
          );
          if (record.clientSessionId.isEmpty || record.userId != userId) return;
          records[key.toString()] = record;
        } catch (error) {
          debugPrint('Invalid queued exercise record: $error');
        }
      });
      return records;
    } catch (error) {
      debugPrint('Pending exercise queue was invalid: $error');
      return <String, PendingExerciseRecord>{};
    }
  }

  Future<void> _saveQueue(
    SharedPreferences prefs,
    String userId,
    Map<String, PendingExerciseRecord> records,
  ) async {
    if (records.isEmpty) {
      await prefs.remove(queuePreferenceKey(userId));
      return;
    }
    await prefs.setString(
      queuePreferenceKey(userId),
      jsonEncode(records.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  /// Serializes brief preference read/modify/write operations per user.
  /// Network and photo I/O stay outside this lock, otherwise a stalled upload
  /// would block a member from persisting a freshly completed workout.
  Future<T> _withQueueLock<T>(
    String userId,
    Future<T> Function() operation,
  ) {
    final previous = _queueOperationTails[userId] ?? Future<void>.value();
    final result = previous.then<T>(
      (_) => operation(),
      onError: (_, __) => operation(),
    );
    late final Future<void> tail;
    tail = result
        .then<void>(
      (_) {},
      onError: (_, __) {},
    )
        .whenComplete(() {
      if (identical(_queueOperationTails[userId], tail)) {
        _queueOperationTails.remove(userId);
      }
    });
    _queueOperationTails[userId] = tail;
    return result;
  }

  String? _currentOwnerToken(String userId) {
    return _ownerTokenProvider(userId);
  }

  bool _stillOwnsSession(String userId, String token) {
    return _ownerTokenProvider(userId) == token;
  }

  void _emit(
    ExerciseSyncPhase phase, {
    String? userId,
    String? clientSessionId,
    String? error,
    List<ActivityStreakMilestone> unlockedMilestones =
        const <ActivityStreakMilestone>[],
  }) {
    status.value = ExerciseSyncStatus(
      phase: phase,
      userId: userId,
      clientSessionId: clientSessionId,
      error: error,
      unlockedMilestones: unlockedMilestones,
    );
  }
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _nullableInt(Object? value) {
  final result = _readInt(value, fallback: -1);
  return result < 0 ? null : result;
}

String _nonEmptyString(Object? value, {String fallback = ''}) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

String? _nullableString(Object? value) {
  final valueAsString = value?.toString().trim() ?? '';
  return valueAsString.isEmpty ? null : valueAsString;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateKey(DateTime value) {
  final date = _dateOnly(value);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime? _parseDateOnly(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return parsed == null ? null : _dateOnly(parsed);
}

bool _isRemoteReference(String reference) {
  final normalized = reference.trim();
  // Older active-session caches stored API-relative media paths. They are
  // already remote; never try to read them from the new local photo store.
  if (normalized.startsWith('/') || normalized.startsWith('storage/')) {
    return true;
  }
  final uri = Uri.tryParse(normalized);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

String _safeErrorMessage(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  if (text.isEmpty) return 'Sync will retry when you are connected.';
  return text.length > 180 ? '${text.substring(0, 177)}...' : text;
}
