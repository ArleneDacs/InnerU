import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/exercise_local_photo_store.dart';
import 'package:selfcare_projects/src/services/pending_exercise_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const memberA = 'member-a';
  const memberB = 'member-b';
  late _MemoryExercisePhotoStore photos;
  late _FakeExerciseGateway gateway;
  late Map<String, String?> ownerTokens;

  PendingExerciseSyncService createService() {
    return PendingExerciseSyncService(
      photoStore: photos,
      gateway: gateway,
      preferencesLoader: SharedPreferences.getInstance,
      ownerTokenProvider: (userId) => ownerTokens[userId],
      streakProcessor: (_) async => const [],
      networkTimeout: const Duration(seconds: 2),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    photos = _MemoryExercisePhotoStore();
    gateway = _FakeExerciseGateway();
    ownerTokens = <String, String?>{
      memberA: 'member-a-token',
      memberB: 'member-b-token',
    };
  });

  test('persists and decodes queued records across a service restart',
      () async {
    final firstService = createService();
    final record = _record(
      'restart-session',
      userId: memberA,
      startedAt: DateTime.utc(2026, 8, 10, 7),
      endedAt: DateTime.utc(2026, 8, 10, 7, 15),
    );
    _seedPhotos(photos, record);

    await firstService.queueCompleted(record);

    final restartedService = createService();
    final recovered = await restartedService.pendingRecords(memberA);

    expect(recovered, hasLength(1));
    expect(recovered.single.clientSessionId, record.clientSessionId);
    expect(recovered.single.userId, memberA);
    expect(
      recovered.single.startedAt.millisecondsSinceEpoch,
      record.startedAt.millisecondsSinceEpoch,
    );
    expect(
      recovered.single.endedAt.millisecondsSinceEpoch,
      record.endedAt.millisecondsSinceEpoch,
    );
    expect(recovered.single.durationSeconds, record.durationSeconds);
    expect(recovered.single.startPhotoReference, record.startPhotoReference);
    expect(recovered.single.endPhotoReference, record.endPhotoReference);
    expect(photos.contains(record.startPhotoReference), isTrue);
    expect(photos.contains(record.endPhotoReference), isTrue);
  });

  test('normalizes a forgotten session longer than 24 hours before it queues',
      () async {
    final endedAt = DateTime.utc(2026, 8, 11, 8, 30);
    final rawStartedAt = endedAt.subtract(const Duration(days: 3));
    final record = _record(
      'forgotten-session',
      userId: memberA,
      startedAt: rawStartedAt,
      endedAt: endedAt,
      durationSeconds: const Duration(days: 3).inSeconds,
    );
    _seedPhotos(photos, record);

    await createService().queueCompleted(record);
    final recovered = (await createService().pendingRecords(memberA)).single;

    expect(recovered.durationSeconds, const Duration(hours: 24).inSeconds);
    expect(
      recovered.startedAt.millisecondsSinceEpoch,
      endedAt
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch,
    );
    expect(recovered.endedAt.millisecondsSinceEpoch, endedAt.millisecondsSinceEpoch);
    expect(recovered.date, '2026-08-11');
  });

  test('shares one in-flight flush for concurrent retry triggers', () async {
    final service = createService();
    final record = _record('single-flight', userId: memberA);
    _seedPhotos(photos, record);
    await service.queueCompleted(record);
    gateway.blockFirstUpload();

    final firstFlush = service.flush(userId: memberA);
    await gateway.firstUploadStarted;
    final secondFlush = service.flush(userId: memberA);

    expect(identical(firstFlush, secondFlush), isTrue);
    expect(gateway.uploadCalls, 1);
    gateway.releaseFirstUpload();
    await Future.wait<void>(<Future<void>>[firstFlush, secondFlush]);

    expect(gateway.uploadCalls, 2);
    expect(gateway.savedSessionIds, <String>[record.clientSessionId]);
    expect(await service.pendingRecords(memberA), isEmpty);
  });

  test('retains the record and both local photos after an upload failure',
      () async {
    final service = createService();
    final record = _record('offline-session', userId: memberA);
    _seedPhotos(photos, record);
    await service.queueCompleted(record);
    gateway.failUploads = true;

    await service.flush(userId: memberA);

    final pending = await service.pendingRecords(memberA);
    expect(pending, hasLength(1));
    expect(pending.single.clientSessionId, record.clientSessionId);
    expect(pending.single.lastSyncError, isNotEmpty);
    expect(gateway.savedSessionIds, isEmpty);
    expect(photos.contains(record.startPhotoReference), isTrue);
    expect(photos.contains(record.endPhotoReference), isTrue);
  });

  test('uploads deterministically, saves once, then removes local references',
      () async {
    final service = createService();
    final record = _record('happy-path', userId: memberA);
    _seedPhotos(photos, record);
    await service.queueCompleted(record);

    await service.flush(userId: memberA);
    await service.flush(userId: memberA);

    expect(
      gateway.events,
      <String>[
        'upload:exercise_happy-path_start.jpg',
        'upload:exercise_happy-path_end.jpg',
        'save:happy-path',
      ],
    );
    expect(gateway.savedSessionIds, <String>['happy-path']);
    expect(await service.pendingRecords(memberA), isEmpty);
    expect(photos.contains(record.startPhotoReference), isFalse);
    expect(photos.contains(record.endPhotoReference), isFalse);
  });

  test('saves optional no-photo records without attempting an image upload',
      () async {
    final service = createService();
    final record = _record(
      'no-photo-session',
      userId: memberA,
      includePhotos: false,
    );

    await service.queueCompleted(record);
    await service.flush(userId: memberA);

    expect(gateway.uploadCalls, 0);
    expect(gateway.savedSessionIds, <String>[record.clientSessionId]);
    expect(gateway.startPhotoUrls, <String?>[null]);
    expect(gateway.endPhotoUrls, <String?>[null]);
    expect(await service.pendingRecords(memberA), isEmpty);
  });

  test('drains a record enqueued while an older record is uploading', () async {
    final service = createService();
    final first = _record(
      'first',
      userId: memberA,
      endedAt: DateTime.utc(2026, 8, 10, 9),
    );
    final second = _record(
      'second',
      userId: memberA,
      endedAt: DateTime.utc(2026, 8, 10, 10),
    );
    _seedPhotos(photos, first);
    _seedPhotos(photos, second);
    await service.queueCompleted(first);
    gateway.blockFirstUpload();

    final flushing = service.flush(userId: memberA);
    await gateway.firstUploadStarted;
    await service.queueCompleted(second);
    gateway.releaseFirstUpload();
    await flushing;

    expect(gateway.savedSessionIds, <String>['first', 'second']);
    expect(await service.pendingRecords(memberA), isEmpty);
    expect(photos.contains(first.startPhotoReference), isFalse);
    expect(photos.contains(second.endPhotoReference), isFalse);
  });

  test('account cleanup prevents a stale flush from recreating old data',
      () async {
    final service = createService();
    final oldRecord = _record('old-account-session', userId: memberA);
    final otherRecord = _record('new-account-session', userId: memberB);
    _seedPhotos(photos, oldRecord);
    _seedPhotos(photos, otherRecord);
    await service.queueCompleted(oldRecord);
    await service.queueCompleted(otherRecord);
    await service.saveActiveSession(
      ExerciseLocalSession(
        clientSessionId: oldRecord.clientSessionId,
        userId: memberA,
        type: oldRecord.type,
        goalDurationSeconds: 300,
        intensity: oldRecord.intensity,
        notes: oldRecord.notes,
        startedAt: oldRecord.startedAt,
        startPhotoReference: oldRecord.startPhotoReference,
      ),
    );
    await service.saveCaptureIntent(
      ExerciseCaptureIntent(
        userId: memberA,
        clientSessionId: oldRecord.clientSessionId,
        slot: ExerciseCaptureSlot.end,
        type: oldRecord.type,
        goalDurationSeconds: 300,
        intensity: oldRecord.intensity,
        notes: oldRecord.notes,
      ),
    );
    gateway.blockFirstUpload();

    final oldFlush = service.flush(userId: memberA);
    await gateway.firstUploadStarted;
    final clearOldAccount = service.clearForUser(memberA);
    ownerTokens[memberA] = null;
    gateway.releaseFirstUpload();
    await Future.wait<void>(<Future<void>>[oldFlush, clearOldAccount]);

    expect(await service.pendingRecords(memberA), isEmpty);
    expect(await service.loadActiveSession(memberA), isNull);
    expect(await service.loadCaptureIntent(memberA), isNull);
    expect(photos.contains(oldRecord.startPhotoReference), isFalse);
    expect(photos.contains(oldRecord.endPhotoReference), isFalse);
    expect(gateway.savedSessionIds, isEmpty);

    expect(
      (await service.pendingRecords(memberB)).single.clientSessionId,
      otherRecord.clientSessionId,
    );
    await service.flush(userId: memberB);
    expect(await service.pendingRecords(memberB), isEmpty);
    expect(gateway.savedSessionIds, <String>[otherRecord.clientSessionId]);
  });
}

PendingExerciseRecord _record(
  String clientSessionId, {
  required String userId,
  DateTime? startedAt,
  DateTime? endedAt,
  int durationSeconds = 300,
  bool includePhotos = true,
}) {
  final resolvedEndedAt = endedAt ?? DateTime.utc(2026, 8, 10, 8, 5);
  final resolvedStartedAt =
      startedAt ?? resolvedEndedAt.subtract(Duration(seconds: durationSeconds));
  return PendingExerciseRecord(
    clientSessionId: clientSessionId,
    userId: userId,
    type: 'Walking',
    durationSeconds: durationSeconds,
    intensity: 2,
    notes: 'local-first test',
    startedAt: resolvedStartedAt,
    endedAt: resolvedEndedAt,
    startPhotoReference:
        includePhotos ? 'memory://$userId/$clientSessionId/start' : null,
    endPhotoReference:
        includePhotos ? 'memory://$userId/$clientSessionId/end' : null,
  );
}

void _seedPhotos(
    _MemoryExercisePhotoStore photos, PendingExerciseRecord record) {
  final start = record.startPhotoReference;
  final end = record.endPhotoReference;
  if (start != null) photos.seed(start, <int>[1, 2, 3]);
  if (end != null) photos.seed(end, <int>[4, 5, 6]);
}

class _MemoryExercisePhotoStore implements ExerciseLocalPhotoStore {
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  void seed(String reference, List<int> bytes) {
    _files[reference] = Uint8List.fromList(bytes);
  }

  bool contains(String? reference) =>
      reference != null && _files.containsKey(reference);

  @override
  Future<void> clearForUser(String userId) async {
    _files.removeWhere(
        (reference, _) => reference.startsWith('memory://$userId/'));
  }

  @override
  Future<Uint8List?> read(String reference) async => _files[reference];

  @override
  Future<void> remove(String reference) async {
    _files.remove(reference);
  }

  @override
  Future<String> save({
    required String userId,
    required String clientSessionId,
    required String slot,
    required Uint8List bytes,
  }) async {
    final reference = 'memory://$userId/$clientSessionId/$slot';
    _files[reference] = Uint8List.fromList(bytes);
    return reference;
  }
}

class _FakeExerciseGateway implements ExerciseSyncGateway {
  final List<String> events = <String>[];
  final List<String> savedSessionIds = <String>[];
  final List<String?> startPhotoUrls = <String?>[];
  final List<String?> endPhotoUrls = <String?>[];
  int uploadCalls = 0;
  bool failUploads = false;
  Completer<void>? _firstUploadStarted;
  Completer<String?>? _firstUploadGate;

  Future<void> get firstUploadStarted => _firstUploadStarted!.future;

  void blockFirstUpload() {
    _firstUploadStarted = Completer<void>();
    _firstUploadGate = Completer<String?>();
  }

  void releaseFirstUpload() {
    _firstUploadGate!.complete('https://example.test/start.jpg');
  }

  @override
  Future<String?> uploadPhoto(
    Uint8List bytes, {
    required String fileName,
  }) async {
    uploadCalls++;
    events.add('upload:$fileName');
    final started = _firstUploadStarted;
    if (uploadCalls == 1 && started != null && !started.isCompleted) {
      started.complete();
    }
    final gate = _firstUploadGate;
    if (uploadCalls == 1 && gate != null) {
      return gate.future;
    }
    if (failUploads) throw StateError('offline');
    return 'https://example.test/$fileName';
  }

  @override
  Future<void> saveRecord(
    PendingExerciseRecord record, {
    String? startPhotoUrl,
    String? endPhotoUrl,
  }) async {
    events.add('save:${record.clientSessionId}');
    savedSessionIds.add(record.clientSessionId);
    startPhotoUrls.add(startPhotoUrl);
    endPhotoUrls.add(endPhotoUrl);
  }
}
