class ExerciseDurationSelection {
  const ExerciseDurationSelection({
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  final int hours;
  final int minutes;
  final int seconds;

  Duration toDuration() {
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  ExerciseDurationSelection copyWith({
    int? hours,
    int? minutes,
    int? seconds,
  }) {
    return ExerciseDurationSelection(
      hours: hours ?? this.hours,
      minutes: minutes ?? this.minutes,
      seconds: seconds ?? this.seconds,
    );
  }
}

Duration exerciseDurationFromSelection(ExerciseDurationSelection selection) {
  return selection.toDuration();
}

ExerciseDurationSelection exerciseDurationSelectionFromDuration(
  Duration duration,
) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return ExerciseDurationSelection(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
  );
}

String formatExerciseDuration(Duration duration) {
  final selection = exerciseDurationSelectionFromDuration(duration);
  final hours = selection.hours;
  final minutes = selection.minutes.toString().padLeft(2, '0');
  final seconds = selection.seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours}h ${minutes}m ${seconds}s';
  }
  return '${selection.minutes}m ${seconds}s';
}
