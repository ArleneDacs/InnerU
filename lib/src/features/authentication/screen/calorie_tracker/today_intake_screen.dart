import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/calorie_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class TodayIntakeScreen extends StatelessWidget {
  const TodayIntakeScreen({super.key});

  static const List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
  ];

  @override
  Widget build(BuildContext context) {
    final session = AuthService.instance.currentSession;
    if (session == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view today\'s intake.'),
        ),
      );
    }

    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final calorieApi = CalorieTrackerApiService.instance;

    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              iconTheme: IconThemeData(color: companyTheme.inkColor),
              title: Text(
                'Today\'s Intake',
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            body: FutureBuilder<Map<String, dynamic>>(
              future: calorieApi.fetchDay(date: todayKey),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final dayResponse = snapshot.data ?? const <String, dynamic>{};
                final dayData = dayResponse['day'] is Map
                    ? (dayResponse['day'] as Map).cast<String, dynamic>()
                    : <String, dynamic>{};
                final waterGlasses =
                    (dayData['waterGlasses'] as num?)?.toInt() ?? 0;
                final waterGoal = (dayData['waterGoal'] as num?)?.toInt() ?? 8;
                final entries = dayResponse['entries'] is List
                    ? (dayResponse['entries'] as List)
                        .whereType<Map>()
                        .map((item) => item.cast<String, dynamic>())
                        .toList()
                    : <Map<String, dynamic>>[];
                final groupedEntries =
                    <String, List<Map<String, dynamic>>>{
                  for (final mealType in _mealTypes) mealType: [],
                };

                for (final entry in entries) {
                  final mealType = (entry['mealType'] as String?) ?? 'Snack';
                  groupedEntries.putIfAbsent(mealType, () => []);
                  groupedEntries[mealType]!.add(entry);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _WaterSummaryCard(
                      waterGlasses: waterGlasses,
                      waterGoal: waterGoal,
                    ),
                    const SizedBox(height: 20),
                    ..._mealTypes.map((mealType) {
                      final mealEntries = groupedEntries[mealType] ?? const [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _MealSectionCard(
                          title: mealType,
                          entries: mealEntries,
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WaterSummaryCard extends StatelessWidget {
  const _WaterSummaryCard({
    required this.waterGlasses,
    required this.waterGoal,
  });

  final int waterGlasses;
  final int waterGoal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = waterGoal <= 0
        ? 0.0
        : (waterGlasses / waterGoal).clamp(0, 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Water Intake Today',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$waterGlasses of $waterGoal glasses',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: theme.colorScheme.surface,
              valueColor:
                  AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealSectionCard extends StatelessWidget {
  const _MealSectionCard({
    required this.title,
    required this.entries,
  });

  final String title;
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    final totalCalories = entries.fold<int>(
      0,
      (sum, doc) => sum + ((doc['calories'] as num?)?.toInt() ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EDE3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$totalCalories kcal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'No entries yet for this meal.',
              style: TextStyle(color: Colors.black54),
            )
          else
            ...entries.map((doc) {
              final meal = (doc['meal'] as String?) ?? 'Meal';
              final calories = (doc['calories'] as num?)?.toInt() ?? 0;
              final protein = (doc['protein'] as num?)?.toInt() ?? 0;
              final carbs = (doc['carbs'] as num?)?.toInt() ?? 0;
              final fat = (doc['fat'] as num?)?.toInt() ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAF5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$calories kcal - P ${protein}g - C ${carbs}g - F ${fat}g',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
