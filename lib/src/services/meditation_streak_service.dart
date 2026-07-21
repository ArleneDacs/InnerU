import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';

enum ActivityStreakType {
  meditation,
  steps,
  exercise,
  fasting,
}

extension ActivityStreakTypeX on ActivityStreakType {
  String get fieldPrefix {
    return switch (this) {
      ActivityStreakType.meditation => 'meditation',
      ActivityStreakType.steps => 'steps',
      ActivityStreakType.exercise => 'exercise',
      ActivityStreakType.fasting => 'fasting',
    };
  }

  String get label {
    return switch (this) {
      ActivityStreakType.meditation => 'Meditation',
      ActivityStreakType.steps => 'Steps',
      ActivityStreakType.exercise => 'Exercise',
      ActivityStreakType.fasting => 'Fasting',
    };
  }
}

class ActivityStreakMilestone {
  const ActivityStreakMilestone({
    required this.id,
    required this.title,
    required this.tier,
    required this.days,
    required this.description,
  });

  final String id;
  final String title;
  final String tier;
  final int days;
  final String description;
}

typedef MeditationStreakMilestone = ActivityStreakMilestone;

class ActivityStreakService {
  ActivityStreakService();

  static const _milestones = {
    ActivityStreakType.meditation: [
      ActivityStreakMilestone(
        id: 'first_breath',
        title: 'First Breath',
        tier: 'Bronze',
        days: 3,
        description: 'Meditated for 3 days in a row.',
      ),
      ActivityStreakMilestone(
        id: 'steady_flame',
        title: 'Steady Flame',
        tier: 'Bronze',
        days: 7,
        description: 'Kept a 7-day meditation streak.',
      ),
      ActivityStreakMilestone(
        id: 'quiet_rhythm',
        title: 'Quiet Rhythm',
        tier: 'Silver',
        days: 14,
        description: 'Made meditation part of two full weeks.',
      ),
      ActivityStreakMilestone(
        id: 'thirty_days_strong',
        title: 'Thirty Days Strong',
        tier: 'Silver',
        days: 30,
        description: 'Completed a full month without breaking the streak.',
      ),
      ActivityStreakMilestone(
        id: 'deep_current',
        title: 'Deep Current',
        tier: 'Gold',
        days: 60,
        description: 'Built a 60-day meditation practice.',
      ),
      ActivityStreakMilestone(
        id: 'unbroken_calm',
        title: 'Unbroken Calm',
        tier: 'Platinum',
        days: 100,
        description: 'Reached 100 days of consistent meditation.',
      ),
    ],
    ActivityStreakType.steps: [
      ActivityStreakMilestone(
        id: 'first_stride',
        title: 'First Stride',
        tier: 'Bronze',
        days: 3,
        description: 'Reached your step goal for 3 days in a row.',
      ),
      ActivityStreakMilestone(
        id: 'steady_steps',
        title: 'Steady Steps',
        tier: 'Bronze',
        days: 7,
        description: 'Kept a 7-day step goal streak.',
      ),
      ActivityStreakMilestone(
        id: 'walking_rhythm',
        title: 'Walking Rhythm',
        tier: 'Silver',
        days: 14,
        description: 'Hit your step goal for two full weeks.',
      ),
      ActivityStreakMilestone(
        id: 'thirty_day_trail',
        title: 'Thirty Day Trail',
        tier: 'Silver',
        days: 30,
        description: 'Completed a full month of daily step goals.',
      ),
      ActivityStreakMilestone(
        id: 'distance_builder',
        title: 'Distance Builder',
        tier: 'Gold',
        days: 60,
        description: 'Built a 60-day movement habit.',
      ),
      ActivityStreakMilestone(
        id: 'unbroken_path',
        title: 'Unbroken Path',
        tier: 'Platinum',
        days: 100,
        description: 'Reached 100 days of daily step goals.',
      ),
    ],
    ActivityStreakType.exercise: [
      ActivityStreakMilestone(
        id: 'first_rep',
        title: 'First Rep',
        tier: 'Bronze',
        days: 3,
        description: 'Logged exercise for 3 days in a row.',
      ),
      ActivityStreakMilestone(
        id: 'training_spark',
        title: 'Training Spark',
        tier: 'Bronze',
        days: 7,
        description: 'Kept a 7-day exercise streak.',
      ),
      ActivityStreakMilestone(
        id: 'strong_rhythm',
        title: 'Strong Rhythm',
        tier: 'Silver',
        days: 14,
        description: 'Made movement part of two full weeks.',
      ),
      ActivityStreakMilestone(
        id: 'thirty_days_stronger',
        title: 'Thirty Days Stronger',
        tier: 'Silver',
        days: 30,
        description: 'Logged exercise for a full month.',
      ),
      ActivityStreakMilestone(
        id: 'power_cycle',
        title: 'Power Cycle',
        tier: 'Gold',
        days: 60,
        description: 'Built a 60-day exercise habit.',
      ),
      ActivityStreakMilestone(
        id: 'unbroken_strength',
        title: 'Unbroken Strength',
        tier: 'Platinum',
        days: 100,
        description: 'Reached 100 days of logged exercise.',
      ),
    ],
    ActivityStreakType.fasting: [
      ActivityStreakMilestone(
        id: 'first_window',
        title: 'First Window',
        tier: 'Bronze',
        days: 3,
        description: 'Completed your fasting goal for 3 days in a row.',
      ),
      ActivityStreakMilestone(
        id: 'steady_window',
        title: 'Steady Window',
        tier: 'Bronze',
        days: 7,
        description: 'Kept a 7-day fasting streak.',
      ),
      ActivityStreakMilestone(
        id: 'clear_rhythm',
        title: 'Clear Rhythm',
        tier: 'Silver',
        days: 14,
        description: 'Completed fasting goals for two full weeks.',
      ),
      ActivityStreakMilestone(
        id: 'thirty_day_window',
        title: 'Thirty Day Window',
        tier: 'Silver',
        days: 30,
        description: 'Completed a full month of fasting goals.',
      ),
      ActivityStreakMilestone(
        id: 'metabolic_rhythm',
        title: 'Metabolic Rhythm',
        tier: 'Gold',
        days: 60,
        description: 'Built a 60-day fasting rhythm.',
      ),
      ActivityStreakMilestone(
        id: 'unbroken_window',
        title: 'Unbroken Window',
        tier: 'Platinum',
        days: 100,
        description: 'Reached 100 days of completed fasting goals.',
      ),
    ],
  };

  static List<ActivityStreakMilestone> milestonesFor(ActivityStreakType type) {
    return _milestones[type] ?? const <ActivityStreakMilestone>[];
  }

  static String currentFieldFor(ActivityStreakType type) {
    return '${type.fieldPrefix}StreakCurrent';
  }

  static String longestFieldFor(ActivityStreakType type) {
    return '${type.fieldPrefix}StreakLongest';
  }

  static String lastDateFieldFor(ActivityStreakType type) {
    return '${type.fieldPrefix}StreakLastDate';
  }

  static String rewardsFieldFor(ActivityStreakType type) {
    return '${type.fieldPrefix}StreakRewards';
  }

  Future<List<ActivityStreakMilestone>> recordCompletedSession({
    required String userId,
    required ActivityStreakType type,
    DateTime? completedAt,
  }) async {
    final date = completedAt ?? DateTime.now();
    final todayKey = _dateKey(date);
    final yesterdayKey = _dateKey(date.subtract(const Duration(days: 1)));
    final currentField = currentFieldFor(type);
    final longestField = longestFieldFor(type);
    final lastDateField = lastDateFieldFor(type);
    final rewardsField = rewardsFieldFor(type);

    final data = await UserService.getUserData();
    final lastDate = data[lastDateField] as String? ??
        data[_snakeToCamel(lastDateField)]?.toString();
    if (lastDate == todayKey) return <ActivityStreakMilestone>[];

    final previousCurrent = _readInt(
      data[currentField] ?? data[_snakeToCamel(currentField)],
    );
    final previousLongest = _readInt(
      data[longestField] ?? data[_snakeToCamel(longestField)],
    );
    final currentStreak = lastDate == yesterdayKey ? previousCurrent + 1 : 1;
    final longestStreak =
        currentStreak > previousLongest ? currentStreak : previousLongest;

    final rewards = _readRewardMap(
      data[rewardsField] ?? data[_snakeToCamel(rewardsField)],
    );
    final unlockedNow = <ActivityStreakMilestone>[];
    for (final milestone in milestonesFor(type)) {
      if (currentStreak >= milestone.days && !rewards.containsKey(milestone.id)) {
        rewards[milestone.id] = todayKey;
        unlockedNow.add(milestone);
      }
    }

    await UserService.updateUserFields({
      currentField: currentStreak,
      longestField: longestStreak,
      lastDateField: todayKey,
      rewardsField: rewards,
    });

    return unlockedNow;
  }

  static int readInt(Object? value) => _readInt(value);

  static Map<String, dynamic> readRewards(Object? value) =>
      _readRewardMap(value);

  static int activeCurrentStreak({
    required Object? lastDate,
    required int currentStreak,
    DateTime? now,
  }) {
    final lastDateKey = lastDate?.toString();
    if (lastDateKey == null || lastDateKey.isEmpty) return 0;

    final date = now ?? DateTime.now();
    final todayKey = _dateKey(date);
    final yesterdayKey = _dateKey(date.subtract(const Duration(days: 1)));
    if (lastDateKey == todayKey || lastDateKey == yesterdayKey) {
      return currentStreak;
    }
    return 0;
  }

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _readRewardMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, rewardValue) => MapEntry('$key', rewardValue));
  }

  static String _snakeToCamel(String value) {
    final parts = value.split('_');
    return parts.first +
        parts.skip(1).map((part) {
          if (part.isEmpty) return part;
          return part[0].toUpperCase() + part.substring(1);
        }).join();
  }
}

class MeditationStreakService {
  MeditationStreakService() : _delegate = ActivityStreakService();

  final ActivityStreakService _delegate;

  static const currentField = 'meditationStreakCurrent';
  static const longestField = 'meditationStreakLongest';
  static const lastDateField = 'meditationStreakLastDate';
  static const rewardsField = 'meditationStreakRewards';

  static List<ActivityStreakMilestone> get milestones =>
      ActivityStreakService.milestonesFor(ActivityStreakType.meditation);

  Future<List<ActivityStreakMilestone>> recordCompletedSession({
    required String userId,
    DateTime? completedAt,
  }) {
    return _delegate.recordCompletedSession(
      userId: userId,
      type: ActivityStreakType.meditation,
      completedAt: completedAt,
    );
  }

  static int readInt(Object? value) => ActivityStreakService.readInt(value);

  static Map<String, dynamic> readRewards(Object? value) =>
      ActivityStreakService.readRewards(value);

  static int activeCurrentStreak({
    required Object? lastDate,
    required int currentStreak,
    DateTime? now,
  }) {
    return ActivityStreakService.activeCurrentStreak(
      lastDate: lastDate,
      currentStreak: currentStreak,
      now: now,
    );
  }
}
