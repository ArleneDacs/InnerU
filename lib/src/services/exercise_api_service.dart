import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';

enum ExerciseGalleryPhotoKind { start, end }

extension ExerciseGalleryPhotoKindLabel on ExerciseGalleryPhotoKind {
  String get label {
    switch (this) {
      case ExerciseGalleryPhotoKind.start:
        return 'Start photo';
      case ExerciseGalleryPhotoKind.end:
        return 'End photo';
    }
  }
}

/// A completed exercise session returned by the bounded gallery endpoint.
///
/// This deliberately retains the two photo URLs on one log. The gallery can
/// render each available image independently while the detail view still has
/// the type, date, and duration from the same immutable session record.
class ExerciseHistoryLog {
  const ExerciseHistoryLog({
    required this.id,
    required this.type,
    required this.durationMinutes,
    required this.durationSeconds,
    required this.intensity,
    required this.notes,
    required this.startPhotoUrl,
    required this.endPhotoUrl,
    required this.date,
    required this.createdAt,
  });

  final String id;
  final String type;
  final int durationMinutes;
  final int durationSeconds;
  final int intensity;
  final String? notes;
  final String? startPhotoUrl;
  final String? endPhotoUrl;
  final String? date;
  final DateTime? createdAt;

  factory ExerciseHistoryLog.fromJson(Map<String, dynamic> json) {
    return ExerciseHistoryLog(
      id: json['id']?.toString() ?? '',
      type: _readTrimmedString(json['type']) ?? 'Exercise',
      durationMinutes: _readExerciseInt(json['durationMinutes']),
      durationSeconds: _readExerciseInt(json['durationSeconds']),
      intensity: _readExerciseInt(json['intensity']),
      notes: _readTrimmedString(json['notes']),
      startPhotoUrl: _readTrimmedString(json['startPhotoUrl']),
      endPhotoUrl: _readTrimmedString(json['endPhotoUrl']),
      date: _readTrimmedString(json['date']),
      createdAt: _readExerciseDateTime(json['createdAt']),
    );
  }

  DateTime? get displayDate => _readExerciseDateTime(date) ?? createdAt;

  List<ExerciseGalleryPhoto> get galleryPhotos {
    final photos = <ExerciseGalleryPhoto>[];
    if (startPhotoUrl != null) {
      photos.add(
        ExerciseGalleryPhoto(
          log: this,
          kind: ExerciseGalleryPhotoKind.start,
          url: startPhotoUrl!,
        ),
      );
    }
    if (endPhotoUrl != null) {
      photos.add(
        ExerciseGalleryPhoto(
          log: this,
          kind: ExerciseGalleryPhotoKind.end,
          url: endPhotoUrl!,
        ),
      );
    }
    return photos;
  }
}

class ExerciseGalleryPhoto {
  const ExerciseGalleryPhoto({
    required this.log,
    required this.kind,
    required this.url,
  });

  final ExerciseHistoryLog log;
  final ExerciseGalleryPhotoKind kind;
  final String url;

  String get heroTag => 'exercise-gallery-${log.id}-${kind.name}';
}

class ExerciseHistoryPage {
  const ExerciseHistoryPage({
    required this.logs,
    required this.page,
    required this.perPage,
    required this.hasMore,
  });

  final List<ExerciseHistoryLog> logs;
  final int page;
  final int perPage;
  final bool hasMore;

  factory ExerciseHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['logs'];
    final logs = rawLogs is List
        ? rawLogs
            .whereType<Map>()
            .map(
              (item) => ExerciseHistoryLog.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false)
        : const <ExerciseHistoryLog>[];

    return ExerciseHistoryPage(
      logs: logs,
      page: _readExerciseInt(json['page'], fallback: 1),
      perPage: _readExerciseInt(json['perPage'], fallback: 18),
      hasMore: _readExerciseBool(json['hasMore']),
    );
  }
}

int _readExerciseInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool _readExerciseBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    return value.toLowerCase() == 'true' || value == '1';
  }
  return false;
}

String? _readTrimmedString(Object? value) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? null : result;
}

DateTime? _readExerciseDateTime(Object? value) {
  final raw = _readTrimmedString(value);
  return raw == null ? null : DateTime.tryParse(raw);
}

class ExerciseApiService {
  ExerciseApiService._();

  static final ExerciseApiService instance = ExerciseApiService._();

  final ApiClient _api = ApiClient.instance;
  String? get _token => AuthService.instance.currentSession?.token;

  Future<List<Map<String, dynamic>>> fetchToday() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final response = await _api.getJson(
      '/api/exercise?date=$today',
      token: _token,
    );
    final logs = response['logs'];
    if (logs is List) {
      return logs
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// Fetch a small page of photo-bearing logs for the exercise gallery.
  /// The API filters out logs without an image, so callers do not spend a
  /// request and layout work on entries that cannot appear in the gallery.
  Future<ExerciseHistoryPage> fetchGalleryHistory({
    int page = 1,
    int perPage = 18,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 30).toInt();
    final response = await _api.getJson(
      '/api/exercise/history?page=$safePage&perPage=$safePerPage',
      token: _token,
    );
    return ExerciseHistoryPage.fromJson(response);
  }

  Future<Map<String, dynamic>> store({
    required String type,
    required int durationMinutes,
    required int durationSeconds,
    required int intensity,
    String? notes,
    String? startPhotoUrl,
    String? endPhotoUrl,
    String? date,
  }) async {
    // Keep all client callers inside the API's seconds contract. The tracker
    // already bounds elapsed time, but this final guard prevents a stale or
    // future caller from creating an unsaveable request with conflicting
    // minutes/seconds values.
    final requestedDuration = durationSeconds > 0
        ? Duration(seconds: durationSeconds)
        : Duration(minutes: durationMinutes);
    final safeDuration = boundedExerciseLogDuration(requestedDuration);
    return _api.postJson(
      '/api/exercise',
      {
        'type': type,
        'duration_minutes': exerciseLogDurationMinutes(safeDuration),
        'duration_seconds': safeDuration.inSeconds,
        'intensity': intensity,
        if (notes != null) 'notes': notes,
        if (startPhotoUrl != null) 'start_photo_url': startPhotoUrl,
        if (endPhotoUrl != null) 'end_photo_url': endPhotoUrl,
        if (date != null) 'date': date,
      },
      token: _token,
    );
  }

  Future<Map<String, dynamic>> delete(String logId) async {
    return _api.deleteJson('/api/exercise/$logId', token: _token);
  }
}
