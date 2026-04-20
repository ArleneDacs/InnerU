import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view today\'s intake.'),
        ),
      );
    }

    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dayRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('calorie_logs')
        .doc(todayKey);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today\'s Intake'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: dayRef.snapshots(),
        builder: (context, daySnapshot) {
          final dayData = daySnapshot.data?.data() ?? {};
          final waterGlasses = (dayData['waterGlasses'] as num?)?.toInt() ?? 0;
          final waterGoal = (dayData['waterGoal'] as num?)?.toInt() ?? 8;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: dayRef
                .collection('entries')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, entriesSnapshot) {
              final entries = entriesSnapshot.data?.docs ?? [];
              final groupedEntries = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{
                for (final mealType in _mealTypes) mealType: [],
              };

              for (final doc in entries) {
                final mealType = (doc.data()['mealType'] as String?) ?? 'Snack';
                groupedEntries.putIfAbsent(mealType, () => []);
                groupedEntries[mealType]!.add(doc);
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
          );
        },
      ),
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
    final progress = waterGoal <= 0 ? 0.0 : (waterGlasses / waterGoal).clamp(0, 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F4FB),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69A9D5).withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.water_drop_outlined, color: Color(0xFF4F96C8)),
              SizedBox(width: 8),
              Text(
                'Water Intake Today',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$waterGlasses of $waterGoal glasses',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF69A9D5)),
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
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> entries;

  @override
  Widget build(BuildContext context) {
    final totalCalories = entries.fold<int>(
      0,
      (sum, doc) => sum + ((doc.data()['calories'] as num?)?.toInt() ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EDE3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              final data = doc.data();
              final meal = (data['meal'] as String?) ?? 'Meal';
              final calories = (data['calories'] as num?)?.toInt() ?? 0;
              final protein = (data['protein'] as num?)?.toInt() ?? 0;
              final carbs = (data['carbs'] as num?)?.toInt() ?? 0;
              final fat = (data['fat'] as num?)?.toInt() ?? 0;

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
