class CalorieFoodPreset {
  const CalorieFoodPreset({
    required this.name,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.aliases,
    required this.defaultUnit,
    required this.gramsPerUnit,
  });

  final String name;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final List<String> aliases;
  final String defaultUnit;
  final double gramsPerUnit;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return name.toLowerCase() == normalized ||
        aliases.any((alias) => alias.toLowerCase() == normalized);
  }
}

class CalorieFoodAmount {
  const CalorieFoodAmount({
    required this.displayName,
    required this.quantityLabel,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final String displayName;
  final String quantityLabel;
  final String unit;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
}

class CalorieTrackerMath {
  const CalorieTrackerMath._();

  static String normalizeMeasurementUnit(String rawUnit) {
    final normalized = rawUnit.trim().toLowerCase();
    if (normalized.isEmpty) return 'piece';
    if (normalized == 'grams' || normalized == 'gram') return 'g';
    if (normalized == 'kilograms' || normalized == 'kilogram') return 'kg';
    if (normalized == 'ounces' || normalized == 'ounce') return 'oz';
    if (normalized == 'pounds' || normalized == 'pound') return 'lb';
    if (normalized == 'milliliters' || normalized == 'milliliter') return 'ml';
    if (normalized == 'liters' ||
        normalized == 'liter' ||
        normalized == 'litres' ||
        normalized == 'litre') {
      return 'liter';
    }
    if (normalized == 'cups') return 'cup';
    if (normalized == 'tablespoons' || normalized == 'tablespoon') {
      return 'tbsp';
    }
    if (normalized == 'teaspoons' || normalized == 'teaspoon') return 'tsp';
    if (normalized == 'slices') return 'slice';
    if (normalized == 'pieces' || normalized == 'pcs' || normalized == 'pc') {
      return 'piece';
    }
    if (normalized.endsWith('ml')) return 'ml';
    if (normalized.endsWith('g')) return 'g';
    return normalized;
  }

  static CalorieFoodPreset? findPresetFood(
    String query,
    Iterable<CalorieFoodPreset> presets,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final preset in presets) {
      if (preset.matches(normalized)) return preset;
    }
    return null;
  }

  static double measurementMultiplier({
    required String unit,
    required double quantity,
    required CalorieFoodPreset preset,
  }) {
    switch (normalizeMeasurementUnit(unit)) {
      case 'g':
        return quantity / preset.gramsPerUnit;
      case 'kg':
        return (quantity * 1000) / preset.gramsPerUnit;
      case 'oz':
        return (quantity * 28.3495) / preset.gramsPerUnit;
      case 'lb':
        return (quantity * 453.592) / preset.gramsPerUnit;
      case 'ml':
        return quantity / preset.gramsPerUnit;
      case 'liter':
        return (quantity * 1000) / preset.gramsPerUnit;
      case 'cup':
        return quantity *
            (preset.defaultUnit == 'cup' ? 1 : 240 / preset.gramsPerUnit);
      case 'tbsp':
        return quantity *
            (preset.defaultUnit == 'tbsp' ? 1 : 15 / preset.gramsPerUnit);
      case 'tsp':
        return quantity *
            (preset.defaultUnit == 'tsp' ? 1 : 5 / preset.gramsPerUnit);
      case 'slice':
        return quantity *
            (preset.defaultUnit == 'slice' ? 1 : 30 / preset.gramsPerUnit);
      case 'serving':
      case 'piece':
      default:
        return quantity;
    }
  }

  static CalorieFoodAmount? calculateFromMeasurement({
    required String mealName,
    required double quantity,
    required String unit,
    required Iterable<CalorieFoodPreset> presets,
  }) {
    final preset = findPresetFood(mealName, presets);
    if (preset == null || quantity <= 0) return null;

    final normalizedUnit = normalizeMeasurementUnit(unit);
    final multiplier = measurementMultiplier(
      unit: normalizedUnit,
      quantity: quantity,
      preset: preset,
    );
    final quantityLabel = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1);

    return CalorieFoodAmount(
      displayName: '$quantityLabel $normalizedUnit ${preset.name}',
      quantityLabel: quantityLabel,
      unit: normalizedUnit,
      calories: (preset.calories * multiplier).round(),
      protein: (preset.protein * multiplier).round(),
      carbs: (preset.carbs * multiplier).round(),
      fat: (preset.fat * multiplier).round(),
    );
  }

  static CalorieFoodAmount? calculateFoodAmount({
    required String query,
    required Iterable<CalorieFoodPreset> presets,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;

    final firstTokenMatch =
        RegExp(r'^(\d+(?:\.\d+)?)([a-zA-Z]+)?$').firstMatch(parts.first);
    final quantity = firstTokenMatch == null
        ? double.tryParse(parts.first)
        : double.tryParse(firstTokenMatch.group(1)!);
    if (quantity == null) return null;

    final inlineUnit = firstTokenMatch?.group(2)?.toLowerCase() ?? '';
    final remaining = parts.skip(1).join(' ').trim();
    if (remaining.isEmpty) return null;

    final unitMatchers = <String>[
      'milliliters',
      'milliliter',
      'ml',
      'slices',
      'slice',
      'tablespoons',
      'tablespoon',
      'tbsp',
      'teaspoons',
      'teaspoon',
      'tsp',
      'grams',
      'gram',
      'g',
      'cups',
      'cup',
      'pieces',
      'piece',
      'pcs',
      'pc',
    ];

    String unit = inlineUnit;
    String foodName = remaining;

    if (unit.isEmpty) {
      for (final matcher in unitMatchers) {
        if (remaining.startsWith('$matcher ')) {
          unit = matcher;
          foodName = remaining.substring(matcher.length).trim();
          break;
        }
      }
    }

    if (foodName.isEmpty) return null;

    final preset = findPresetFood(foodName, presets);
    if (preset == null) return null;

    final normalizedUnit = unit.isEmpty ? preset.defaultUnit : unit;
    double multiplier;

    if (normalizedUnit == 'g' ||
        normalizedUnit == 'gram' ||
        normalizedUnit == 'grams' ||
        normalizedUnit == 'ml' ||
        normalizedUnit == 'milliliter' ||
        normalizedUnit == 'milliliters') {
      multiplier = quantity / preset.gramsPerUnit;
    } else if (normalizedUnit == 'cup' || normalizedUnit == 'cups') {
      if (preset.defaultUnit != 'cup') return null;
      multiplier = quantity;
    } else if (normalizedUnit == 'slice' || normalizedUnit == 'slices') {
      if (preset.defaultUnit != 'slice') return null;
      multiplier = quantity;
    } else if (normalizedUnit == 'tbsp' ||
        normalizedUnit == 'tablespoon' ||
        normalizedUnit == 'tablespoons') {
      if (preset.defaultUnit != 'tbsp') return null;
      multiplier = quantity;
    } else if (normalizedUnit == 'tsp' ||
        normalizedUnit == 'teaspoon' ||
        normalizedUnit == 'teaspoons') {
      if (preset.defaultUnit != 'tsp') return null;
      multiplier = quantity;
    } else {
      multiplier = quantity;
    }

    final quantityLabel = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();

    return CalorieFoodAmount(
      displayName:
          '$quantityLabel ${unit.isEmpty ? preset.defaultUnit : unit} ${preset.name}',
      quantityLabel: quantityLabel,
      unit: normalizeMeasurementUnit(unit.isEmpty ? preset.defaultUnit : unit),
      calories: (preset.calories * multiplier).round(),
      protein: (preset.protein * multiplier).round(),
      carbs: (preset.carbs * multiplier).round(),
      fat: (preset.fat * multiplier).round(),
    );
  }
}
