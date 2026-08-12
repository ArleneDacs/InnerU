import 'exercise_local_photo_store_base.dart';
import 'exercise_local_photo_store_io.dart'
    if (dart.library.html) 'exercise_local_photo_store_web.dart' as platform;

export 'exercise_local_photo_store_base.dart';

ExerciseLocalPhotoStore createExerciseLocalPhotoStore() {
  return platform.createExerciseLocalPhotoStore();
}
