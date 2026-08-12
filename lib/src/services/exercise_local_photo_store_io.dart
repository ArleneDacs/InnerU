import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'exercise_local_photo_store_base.dart';

ExerciseLocalPhotoStore createExerciseLocalPhotoStore() =>
    _IoExerciseLocalPhotoStore();

class _IoExerciseLocalPhotoStore implements ExerciseLocalPhotoStore {
  static const _directoryName = 'exercise_local_photos';

  String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  Future<Directory> _userDirectory(String userId) async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/$_directoryName/${_safeSegment(userId)}');
  }

  @override
  Future<String> save({
    required String userId,
    required String clientSessionId,
    required String slot,
    required Uint8List bytes,
  }) async {
    final directory = await _userDirectory(userId);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/${_safeSegment(clientSessionId)}_${_safeSegment(slot)}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.uri.toString();
  }

  @override
  Future<Uint8List?> read(String reference) async {
    final uri = Uri.tryParse(reference);
    if (uri == null || uri.scheme != 'file') return null;
    final file = File.fromUri(uri);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> remove(String reference) async {
    final uri = Uri.tryParse(reference);
    if (uri == null || uri.scheme != 'file') return;
    final file = File.fromUri(uri);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> clearForUser(String userId) async {
    final directory = await _userDirectory(userId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
