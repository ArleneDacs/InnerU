import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_math.dart';

void main() {
  const presets = <CalorieFoodPreset>[
    CalorieFoodPreset(
      name: 'Boiled Egg',
      calories: 78,
      protein: 6,
      carbs: 1,
      fat: 5,
      aliases: ['egg', 'eggs', 'boiled egg', 'boiled eggs'],
      defaultUnit: 'piece',
      gramsPerUnit: 50.0,
    ),
    CalorieFoodPreset(
      name: 'Chicken Breast',
      calories: 165,
      protein: 31,
      carbs: 0,
      fat: 4,
      aliases: ['chicken breast', 'chicken'],
      defaultUnit: '100g',
      gramsPerUnit: 100.0,
    ),
    CalorieFoodPreset(
      name: 'White Rice',
      calories: 205,
      protein: 4,
      carbs: 45,
      fat: 0,
      aliases: ['white rice', 'rice'],
      defaultUnit: 'cup',
      gramsPerUnit: 158.0,
    ),
  ];

  group('CalorieTrackerMath', () {
    test('normalizes common units', () {
      expect(CalorieTrackerMath.normalizeMeasurementUnit('grams'), 'g');
      expect(CalorieTrackerMath.normalizeMeasurementUnit('LITERS'), 'liter');
      expect(CalorieTrackerMath.normalizeMeasurementUnit('pc'), 'piece');
      expect(CalorieTrackerMath.normalizeMeasurementUnit(''), 'piece');
    });

    test('finds presets by name and alias', () {
      expect(
        CalorieTrackerMath.findPresetFood('eggs', presets)?.name,
        'Boiled Egg',
      );
      expect(
        CalorieTrackerMath.findPresetFood('rice', presets)?.name,
        'White Rice',
      );
    });

    test('calculates direct measurement servings accurately', () {
      final result = CalorieTrackerMath.calculateFromMeasurement(
        mealName: 'White Rice',
        quantity: 2,
        unit: 'cup',
        presets: presets,
      );

      expect(result, isNotNull);
      expect(result!.displayName, '2 cup White Rice');
      expect(result.quantityLabel, '2');
      expect(result.unit, 'cup');
      expect(result.calories, 410);
      expect(result.protein, 8);
      expect(result.carbs, 90);
      expect(result.fat, 0);
    });

    test('parses typed quantity plus grams and rounds macros correctly', () {
      final result = CalorieTrackerMath.calculateFoodAmount(
        query: '150g chicken breast',
        presets: presets,
      );

      expect(result, isNotNull);
      expect(result!.displayName, '150 g Chicken Breast');
      expect(result.quantityLabel, '150');
      expect(result.unit, 'g');
      expect(result.calories, 248);
      expect(result.protein, 47);
      expect(result.carbs, 0);
      expect(result.fat, 6);
    });

    test('parses alias-based preset quantities from plain text', () {
      final result = CalorieTrackerMath.calculateFoodAmount(
        query: '3 eggs',
        presets: presets,
      );

      expect(result, isNotNull);
      expect(result!.displayName, '3 piece Boiled Egg');
      expect(result.quantityLabel, '3');
      expect(result.unit, 'piece');
      expect(result.calories, 234);
      expect(result.protein, 18);
      expect(result.carbs, 3);
      expect(result.fat, 15);
    });
  });
}
