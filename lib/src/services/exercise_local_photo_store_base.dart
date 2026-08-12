import 'dart:typed_data';

/// Persistent storage for a camera image captured as part of an exercise.
///
/// References are intentionally opaque to callers. Native platforms use a
/// private app-support file, while web stores a compact base64 value under the
/// same user-scoped queue. Keeping the reference opaque lets the sync queue
/// recover a photo after a restart without ever treating an unuploaded image
/// as a remote URL.
abstract class ExerciseLocalPhotoStore {
  Future<String> save({
    required String userId,
    required String clientSessionId,
    required String slot,
    required Uint8List bytes,
  });

  Future<Uint8List?> read(String reference);

  Future<void> remove(String reference);

  Future<void> clearForUser(String userId);
}
