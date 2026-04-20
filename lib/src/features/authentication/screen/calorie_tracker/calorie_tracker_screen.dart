import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/barcode_scanner_screen.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';

class CalorieTrackerScreen extends StatefulWidget {
  const CalorieTrackerScreen({super.key});

  @override
  State<CalorieTrackerScreen> createState() => _CalorieTrackerScreenState();
}

class _CalorieTrackerScreenState extends State<CalorieTrackerScreen> {
  static const List<_PresetFood> _presetFoods = [
    _PresetFood(
      name: 'Boiled Egg',
      calories: 78,
      protein: 6,
      carbs: 1,
      fat: 5,
      aliases: ['egg', 'eggs', 'boiled egg', 'boiled eggs'],
      defaultUnit: 'piece',
      gramsPerUnit: 50,
    ),
    _PresetFood(
      name: 'Chicken Breast',
      calories: 165,
      protein: 31,
      carbs: 0,
      fat: 4,
      aliases: ['chicken breast', 'chicken'],
      defaultUnit: '100g',
      gramsPerUnit: 100,
    ),
    _PresetFood(
      name: 'White Rice',
      calories: 205,
      protein: 4,
      carbs: 45,
      fat: 0,
      aliases: ['white rice', 'rice'],
      defaultUnit: 'cup',
      gramsPerUnit: 158,
    ),
    _PresetFood(
      name: 'Banana',
      calories: 105,
      protein: 1,
      carbs: 27,
      fat: 0,
      aliases: ['banana', 'bananas'],
      defaultUnit: 'piece',
      gramsPerUnit: 118,
    ),
    _PresetFood(
      name: 'Apple',
      calories: 95,
      protein: 0,
      carbs: 25,
      fat: 0,
      aliases: ['apple', 'apples'],
      defaultUnit: 'piece',
      gramsPerUnit: 182,
    ),
    _PresetFood(
      name: 'Greek Yogurt',
      calories: 120,
      protein: 17,
      carbs: 7,
      fat: 2,
      aliases: ['greek yogurt', 'yogurt'],
      defaultUnit: 'cup',
      gramsPerUnit: 170,
    ),
    _PresetFood(
      name: 'Milk',
      calories: 103,
      protein: 8,
      carbs: 12,
      fat: 2,
      aliases: ['milk'],
      defaultUnit: '250ml',
      gramsPerUnit: 250,
    ),
    _PresetFood(
      name: 'Bread',
      calories: 80,
      protein: 3,
      carbs: 15,
      fat: 1,
      aliases: ['bread', 'toast'],
      defaultUnit: 'slice',
      gramsPerUnit: 30,
    ),
    _PresetFood(
      name: 'Peanut Butter',
      calories: 95,
      protein: 4,
      carbs: 3,
      fat: 8,
      aliases: ['peanut butter'],
      defaultUnit: 'tbsp',
      gramsPerUnit: 16,
    ),
    _PresetFood(
      name: 'Olive Oil',
      calories: 40,
      protein: 0,
      carbs: 0,
      fat: 5,
      aliases: ['olive oil'],
      defaultUnit: 'tsp',
      gramsPerUnit: 5,
    ),
  ];

  static const List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
  ];
  static const List<String> _measurementUnits = [
    'piece',
    'g',
    'kg',
    'oz',
    'lb',
    'ml',
    'liter',
    'cup',
    'tbsp',
    'tsp',
    'slice',
    'serving',
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _mealController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();

  Timer? _searchDebounce;
  Timer? _goalHintTimer;
  int _dailyGoal = 2000;
  int _dailyWaterGoal = 8;
  bool _isSavingGoal = false;
  bool _isLookingUpFood = false;
  bool _isSearchingSuggestions = false;
  bool _isCapturingMealPhoto = false;
  bool _showPresetFoods = false;
  bool _showGoalHintBubble = false;
  String _selectedMealType = 'Breakfast';
  String _selectedMeasurementUnit = 'piece';
  String? _mealPhotoPath;
  List<_NutritionLookupResult> _onlineSuggestions = [];

  String get _userId => _auth.currentUser!.uid;
  String get _todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());

  DocumentReference<Map<String, dynamic>> get _dayRef => _firestore
      .collection('users')
      .doc(_userId)
      .collection('calorie_logs')
      .doc(_todayKey);

  @override
  void initState() {
    super.initState();
    _loadGoal();
    _showGoalHint();
  }

  void _showGoalHint() {
    _goalHintTimer?.cancel();
    _showGoalHintBubble = true;
    _goalHintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showGoalHintBubble = false;
      });
    });
  }

  void _dismissGoalHint() {
    _goalHintTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _showGoalHintBubble = false;
    });
  }

  Future<void> _loadGoal() async {
    try {
      final snapshot = await _dayRef.get();
      final data = snapshot.data();
      final goal = (data?['dailyGoal'] as num?)?.toInt();
      if (goal != null && mounted) {
        setState(() {
          _dailyGoal = goal;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveGoalValue(int goal) async {
    if (goal <= 0) {
      _showSnackBar('Enter a valid calorie goal.');
      return;
    }

    setState(() {
      _isSavingGoal = true;
    });

    try {
      await _dayRef.set({
        'dailyGoal': goal,
        'date': _todayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _dailyGoal = goal;
      });
    } catch (_) {
      _showSnackBar('Failed to save calorie goal.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingGoal = false;
        });
      }
    }
  }

  Future<void> _editGoalFromProgressCard(int currentGoal) async {
    final controller = TextEditingController(
      text: (currentGoal > 0 ? currentGoal : _dailyGoal).toString(),
    );

    final parsedGoal = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Daily Calorie Goal'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ex. 2200',
              helperText: 'This is your target calorie intake for the day.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                int.tryParse(controller.text.trim()),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (parsedGoal == null) return;
    await _saveGoalValue(parsedGoal);
  }

  Future<void> _openCalorieCalculator() async {
    final ageController = TextEditingController();
    final weightController = TextEditingController();
    final heightController = TextEditingController();
    String selectedSex = 'Male';
    double activityMultiplier = 1.375;
    String activityLabel = 'Lightly active';

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Calorie Intake Calculator'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedSex,
                      decoration: const InputDecoration(labelText: 'Sex'),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedSex = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        hintText: 'Ex. 24',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: weightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        hintText: 'Ex. 65',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: heightController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Height (cm)',
                        hintText: 'Ex. 170',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: activityLabel,
                      decoration: const InputDecoration(labelText: 'Activity'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Sedentary',
                          child: Text('Sedentary'),
                        ),
                        DropdownMenuItem(
                          value: 'Lightly active',
                          child: Text('Lightly active'),
                        ),
                        DropdownMenuItem(
                          value: 'Moderately active',
                          child: Text('Moderately active'),
                        ),
                        DropdownMenuItem(
                          value: 'Very active',
                          child: Text('Very active'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          activityLabel = value;
                          activityMultiplier = switch (value) {
                            'Sedentary' => 1.2,
                            'Moderately active' => 1.55,
                            'Very active' => 1.725,
                            _ => 1.375,
                          };
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final age = double.tryParse(ageController.text.trim());
                    final weight = double.tryParse(weightController.text.trim());
                    final height = double.tryParse(heightController.text.trim());

                    if (age == null ||
                        weight == null ||
                        height == null ||
                        age <= 0 ||
                        weight <= 0 ||
                        height <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter valid age, weight, and height.'),
                        ),
                      );
                      return;
                    }

                    final bmr = selectedSex == 'Male'
                        ? 10 * weight + 6.25 * height - 5 * age + 5
                        : 10 * weight + 6.25 * height - 5 * age - 161;
                    Navigator.pop(context, (bmr * activityMultiplier).round());
                  },
                  child: const Text('Calculate'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    final shouldUse = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Use Suggested Intake?'),
          content: Text(
            'Your estimated daily calorie intake is $result kcal. Do you want to use this as your daily goal?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not Now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use This'),
            ),
          ],
        );
      },
    );

    if (shouldUse != true) return;
    await _saveGoalValue(result);
    if (!mounted) return;
    _showSnackBar('Daily goal updated to $result kcal.');
  }

  Future<void> _captureMealPhoto() async {
    if (_isCapturingMealPhoto) return;

    setState(() {
      _isCapturingMealPhoto = true;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;
      setState(() {
        _mealPhotoPath = image.path;
      });

      await _promptCameraMealLabel();
    } catch (_) {
      _showSnackBar('Could not open the camera.');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingMealPhoto = false;
        });
      }
    }
  }

  Future<void> _promptCameraMealLabel() async {
    final controller = TextEditingController(text: _mealController.text.trim());
    final mealName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('What food is this?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Ex. Chicken burger, fries, milk tea',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Use This'),
            ),
          ],
        );
      },
    );

    if (!mounted || mealName == null || mealName.isEmpty) return;
    _mealController.text = mealName;
    _handleMealNameChanged(mealName);
    await _ensureNutritionForMeal(mealName);
  }

  Future<String?> _uploadMealPhotoIfNeeded() async {
    final photoPath = _mealPhotoPath;
    if (photoPath == null || photoPath.isEmpty) return null;
    if (!ImageStorageService.isConfigured) return null;

    try {
      final bytes = await File(photoPath).readAsBytes();
      return await ImageStorageService.uploadImageBytes(
        bytes,
        fileName: 'meal_${_userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (_) {
      return null;
    }
  }

  void _clearMealComposer() {
    _mealController.clear();
    _quantityController.clear();
    _calorieController.clear();
    _proteinController.clear();
    _carbController.clear();
    _fatController.clear();
    _searchDebounce?.cancel();

    setState(() {
      _mealPhotoPath = null;
      _onlineSuggestions = [];
      _isSearchingSuggestions = false;
      _selectedMealType = 'Breakfast';
      _selectedMeasurementUnit = 'piece';
    });
  }

  Future<void> _addMeal() async {
    final mealName = _mealController.text.trim();
    if (mealName.isEmpty) {
      _showSnackBar('Enter a meal name first.');
      return;
    }

    final lookedUpNutrition = await _ensureNutritionForMeal(mealName);
    final calories = int.tryParse(_calorieController.text.trim());
    final protein = int.tryParse(_proteinController.text.trim()) ?? 0;
    final carbs = int.tryParse(_carbController.text.trim()) ?? 0;
    final fat = int.tryParse(_fatController.text.trim()) ?? 0;

    if (calories == null || calories <= 0) {
      _showSnackBar(
        lookedUpNutrition == null
            ? 'Could not detect calories automatically. Please enter them manually.'
            : 'Enter a valid calorie amount.',
      );
      return;
    }

    try {
      final photoUrl = await _uploadMealPhotoIfNeeded();
      final quantity = double.tryParse(_quantityController.text.trim());

      await _dayRef.set({
        'dailyGoal': _dailyGoal,
        'date': _todayKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _dayRef.collection('entries').add({
        'meal': mealName,
        'mealType': _selectedMealType,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'quantity': quantity,
        'measurementUnit': _selectedMeasurementUnit,
        'photoUrl': photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _refreshDailyTotals();
      _clearMealComposer();
      FocusScope.of(context).unfocus();
    } catch (_) {
      _showSnackBar('Failed to add meal.');
    }
  }

  Future<void> _refreshDailyTotals() async {
    final snapshot = await _dayRef.collection('entries').get();
    int totalCalories = 0;
    int totalProtein = 0;
    int totalCarbs = 0;
    int totalFat = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      totalCalories += (data['calories'] as num?)?.toInt() ?? 0;
      totalProtein += (data['protein'] as num?)?.toInt() ?? 0;
      totalCarbs += (data['carbs'] as num?)?.toInt() ?? 0;
      totalFat += (data['fat'] as num?)?.toInt() ?? 0;
    }

    await _dayRef.set({
      'date': _todayKey,
      'dailyGoal': _dailyGoal,
      'totalCalories': totalCalories,
      'totalProtein': totalProtein,
      'totalCarbs': totalCarbs,
      'totalFat': totalFat,
      'mealCount': snapshot.docs.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setWaterGlasses(int glasses) async {
    final clamped = glasses.clamp(0, 20);

    try {
      await _dayRef.set({
        'date': _todayKey,
        'dailyGoal': _dailyGoal,
        'waterGlasses': clamped,
        'waterGoal': _dailyWaterGoal,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      _showSnackBar('Failed to update water tracker.');
    }
  }

  void _applyPresetFood(_PresetFood preset) {
    _mealController.text = preset.name;
    _calorieController.text = preset.calories.toString();
    _proteinController.text = preset.protein.toString();
    _carbController.text = preset.carbs.toString();
    _fatController.text = preset.fat.toString();
    setState(() {
      _selectedMeasurementUnit = _normalizeMeasurementUnit(preset.defaultUnit);
    });
  }

  void _applyFoodAmount(_CalculatedFoodAmount calculated) {
    _mealController.text = calculated.displayName;
    _calorieController.text = calculated.calories.toString();
    _proteinController.text = calculated.protein.toString();
    _carbController.text = calculated.carbs.toString();
    _fatController.text = calculated.fat.toString();
    _quantityController.text = calculated.quantityLabel;
    setState(() {
      _selectedMeasurementUnit = calculated.unit;
    });
  }

  _PresetFood? _findPresetFood(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final preset in _presetFoods) {
      if (preset.matches(normalized)) return preset;
    }
    return null;
  }

  String _normalizeMeasurementUnit(String rawUnit) {
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
    if (normalized == 'tablespoons' || normalized == 'tablespoon') return 'tbsp';
    if (normalized == 'teaspoons' || normalized == 'teaspoon') return 'tsp';
    if (normalized == 'slices') return 'slice';
    if (normalized == 'pieces' || normalized == 'pcs' || normalized == 'pc') {
      return 'piece';
    }
    if (normalized.endsWith('ml')) return 'ml';
    if (normalized.endsWith('g')) return 'g';
    return normalized;
  }

  double _measurementMultiplier(String unit, double quantity, _PresetFood preset) {
    switch (_normalizeMeasurementUnit(unit)) {
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
        return quantity * (preset.defaultUnit == 'cup' ? 1 : 240 / preset.gramsPerUnit);
      case 'tbsp':
        return quantity * (preset.defaultUnit == 'tbsp' ? 1 : 15 / preset.gramsPerUnit);
      case 'tsp':
        return quantity * (preset.defaultUnit == 'tsp' ? 1 : 5 / preset.gramsPerUnit);
      case 'slice':
        return quantity * (preset.defaultUnit == 'slice' ? 1 : 30 / preset.gramsPerUnit);
      case 'serving':
      case 'piece':
      default:
        return quantity;
    }
  }

  _CalculatedFoodAmount? _calculateFromMeasurement({
    required String mealName,
    required double quantity,
    required String unit,
  }) {
    final preset = _findPresetFood(mealName);
    if (preset == null || quantity <= 0) return null;

    final normalizedUnit = _normalizeMeasurementUnit(unit);
    final multiplier = _measurementMultiplier(normalizedUnit, quantity, preset);
    final quantityLabel = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1);

    return _CalculatedFoodAmount(
      displayName: '$quantityLabel $normalizedUnit ${preset.name}',
      quantityLabel: quantityLabel,
      unit: normalizedUnit,
      calories: (preset.calories * multiplier).round(),
      protein: (preset.protein * multiplier).round(),
      carbs: (preset.carbs * multiplier).round(),
      fat: (preset.fat * multiplier).round(),
    );
  }

  _CalculatedFoodAmount? _calculateFoodAmount(String query) {
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

    final preset = _findPresetFood(foodName);
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

    return _CalculatedFoodAmount(
      displayName: '$quantityLabel ${unit.isEmpty ? preset.defaultUnit : unit} ${preset.name}',
      quantityLabel: quantityLabel,
      unit: _normalizeMeasurementUnit(unit.isEmpty ? preset.defaultUnit : unit),
      calories: (preset.calories * multiplier).round(),
      protein: (preset.protein * multiplier).round(),
      carbs: (preset.carbs * multiplier).round(),
      fat: (preset.fat * multiplier).round(),
    );
  }

  void _handleMealNameChanged(String value) {
    final measuredAmount = _calculateAmountFromFields(value);
    if (measuredAmount != null) {
      _applyFoodAmount(measuredAmount);
      setState(() {
        _onlineSuggestions = [];
      });
      return;
    }

    final calculatedAmount = _calculateFoodAmount(value);
    if (calculatedAmount != null) {
      _applyFoodAmount(calculatedAmount);
      setState(() {
        _onlineSuggestions = [];
      });
      return;
    }

    final preset = _findPresetFood(value);
    if (preset != null) {
      _applyPresetFood(preset);
      setState(() {
        _onlineSuggestions = [];
      });
      return;
    }

    _queueSuggestionSearch(value);
  }

  _CalculatedFoodAmount? _calculateAmountFromFields(String mealName) {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) return null;

    return _calculateFromMeasurement(
      mealName: mealName,
      quantity: quantity,
      unit: _selectedMeasurementUnit,
    );
  }

  Future<_NutritionLookupResult?> _ensureNutritionForMeal(String mealName) async {
    final existingCalories = int.tryParse(_calorieController.text.trim());
    if (existingCalories != null && existingCalories > 0) return null;

    final measuredAmount = _calculateAmountFromFields(mealName);
    if (measuredAmount != null) {
      _applyFoodAmount(measuredAmount);
      return _NutritionLookupResult(
        displayName: measuredAmount.displayName,
        calories: measuredAmount.calories,
        protein: measuredAmount.protein,
        carbs: measuredAmount.carbs,
        fat: measuredAmount.fat,
      );
    }

    final calculatedAmount = _calculateFoodAmount(mealName);
    if (calculatedAmount != null) {
      _applyFoodAmount(calculatedAmount);
      return _NutritionLookupResult(
        displayName: calculatedAmount.displayName,
        calories: calculatedAmount.calories,
        protein: calculatedAmount.protein,
        carbs: calculatedAmount.carbs,
        fat: calculatedAmount.fat,
      );
    }

    final preset = _findPresetFood(mealName);
    if (preset != null) {
      _applyPresetFood(preset);
      return _NutritionLookupResult(
        displayName: preset.name,
        calories: preset.calories,
        protein: preset.protein,
        carbs: preset.carbs,
        fat: preset.fat,
      );
    }

    return _lookupFoodOnline(mealName);
  }

  Future<_NutritionLookupResult?> _lookupFoodOnline(String mealName) async {
    if (_isLookingUpFood) return null;

    setState(() {
      _isLookingUpFood = true;
    });

    try {
      final suggestions = await _fetchOnlineSuggestions(mealName, limit: 1);
      if (suggestions.isEmpty) return null;
      final result = suggestions.first;
      _applyOnlineSuggestion(result);
      return result;
    } on TimeoutException {
      _showSnackBar('Food lookup timed out. You can still enter calories manually.');
    } catch (_) {
      // leave manual entry available
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUpFood = false;
        });
      }
    }

    return null;
  }

  Future<List<_NutritionLookupResult>> _fetchOnlineSuggestions(
    String mealName, {
    int limit = 5,
  }) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/cgi/search.pl',
      {
        'search_terms': mealName,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '$limit',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'InnerU-SelfcareApp/1.0 (food calorie lookup)',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return const [];

    final payload = json.decode(response.body) as Map<String, dynamic>;
    final products = (payload['products'] as List?) ?? const [];
    final suggestions = <_NutritionLookupResult>[];

    for (final product in products) {
      if (product is! Map<String, dynamic>) continue;
      final result = _nutritionFromProductMap(product);
      if (result != null) suggestions.add(result);
    }

    return suggestions;
  }

  _NutritionLookupResult? _nutritionFromProductMap(Map<String, dynamic> product) {
    final nutriments = product['nutriments'];
    if (nutriments is! Map<String, dynamic>) return null;

    final servingCalories = (nutriments['energy-kcal_serving'] as num?)?.toDouble();
    final servingProtein = (nutriments['proteins_serving'] as num?)?.toDouble();
    final servingCarbs =
        (nutriments['carbohydrates_serving'] as num?)?.toDouble();
    final servingFat = (nutriments['fat_serving'] as num?)?.toDouble();
    final hundredCalories = (nutriments['energy-kcal_100g'] as num?)?.toDouble();
    final hundredProtein = (nutriments['proteins_100g'] as num?)?.toDouble();
    final hundredCarbs =
        (nutriments['carbohydrates_100g'] as num?)?.toDouble();
    final hundredFat = (nutriments['fat_100g'] as num?)?.toDouble();

    final calories = servingCalories ?? hundredCalories;
    if (calories == null || calories <= 0) return null;

    final productName = (product['product_name'] as String?)?.trim();
    final brands = (product['brands'] as String?)?.trim();
    final amountSuffix = servingCalories != null ? 'serving' : '100g';
    final displayName = productName == null || productName.isEmpty
        ? 'Food ($amountSuffix)'
        : '$productName ($amountSuffix)';

    return _NutritionLookupResult(
      displayName: displayName,
      calories: calories.round(),
      protein: (servingProtein ?? hundredProtein ?? 0).round(),
      carbs: (servingCarbs ?? hundredCarbs ?? 0).round(),
      fat: (servingFat ?? hundredFat ?? 0).round(),
      subtitle: brands == null || brands.isEmpty ? null : brands,
    );
  }

  void _queueSuggestionSearch(String query) {
    _searchDebounce?.cancel();

    if (query.trim().length < 3) {
      if (mounted) {
        setState(() {
          _onlineSuggestions = [];
          _isSearchingSuggestions = false;
        });
      }
      return;
    }

    setState(() {
      _isSearchingSuggestions = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await _fetchOnlineSuggestions(query, limit: 6);
        if (!mounted) return;
        setState(() {
          _onlineSuggestions = results;
          _isSearchingSuggestions = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _onlineSuggestions = [];
          _isSearchingSuggestions = false;
        });
      }
    });
  }

  void _applyOnlineSuggestion(_NutritionLookupResult suggestion) {
    _mealController.text = suggestion.displayName;
    _calorieController.text = suggestion.calories.toString();
    _proteinController.text = suggestion.protein.toString();
    _carbController.text = suggestion.carbs.toString();
    _fatController.text = suggestion.fat.toString();

    setState(() {
      _onlineSuggestions = [];
    });
  }

  Future<void> _scanBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );

    if (barcode == null || barcode.isEmpty) return;

    setState(() {
      _isLookingUpFood = true;
    });

    try {
      final uri = Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/$barcode',
        {
          'fields': 'product_name,brands,nutriments',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'InnerU-SelfcareApp/1.0 (barcode food lookup)',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _showSnackBar('Could not fetch barcode nutrition info.');
        return;
      }

      final payload = json.decode(response.body) as Map<String, dynamic>;
      final product = payload['product'];
      if (product is! Map<String, dynamic>) {
        _showSnackBar('No nutrition data found for that barcode.');
        return;
      }

      final result = _nutritionFromProductMap(product);
      if (result == null) {
        _showSnackBar('No nutrition data found for that barcode.');
        return;
      }

      _applyOnlineSuggestion(result);
    } on TimeoutException {
      _showSnackBar('Barcode lookup timed out. Please try again.');
    } catch (_) {
      _showSnackBar('Barcode lookup failed.');
    } finally {
      if (mounted) {
        setState(() {
          _isLookingUpFood = false;
        });
      }
    }
  }

  int _weeklyTotal(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String key) {
    return docs.fold<int>(
      0,
      (sum, doc) => sum + ((doc.data()[key] as num?)?.toInt() ?? 0),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _goalHintTimer?.cancel();
    _mealController.dispose();
    _quantityController.dispose();
    _calorieController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Widget _macroTile(String label, int grams, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.84),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              width: 26,
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${grams}g',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyProgressCard({
    required int totalCalories,
    required int currentGoal,
    required int totalCarbs,
    required int totalProtein,
    required int totalFat,
    required int mealCount,
    required double progress,
  }) {
    final goalLabel = currentGoal <= 0 ? '--' : currentGoal.toString();
    final progressPercent = (progress * 100).round().clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD9EFD6),
            Color(0xFFB7D9B2),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF90A17D).withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Daily Progress',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isSavingGoal ? null : () => _editGoalFromProgressCard(currentGoal),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(text: totalCalories.toString()),
                        TextSpan(
                          text: '/$goalLabel Kcal',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showGoalHintBubble) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 230),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4D6A45),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Tap the Kcal target to change your goal.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismissGoalHint,
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ArcProgressPainter(
                      progress: progress,
                      backgroundColor: Colors.white.withOpacity(0.7),
                      progressColor: const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Color(0xFFE28B54),
                      size: 20,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totalCalories.toString(),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                    ),
                    const Text(
                      'Calories',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Positioned(
                  left: 10,
                  bottom: 18,
                  child: Text(
                    '0%',
                    style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 18,
                  child: Text(
                    '$progressPercent%',
                    style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _macroTile('Carbs', totalCarbs, const Color(0xFF8FAF86)),
              const SizedBox(width: 10),
              _macroTile('Protein', totalProtein, const Color(0xFFE06464)),
              const SizedBox(width: 10),
              _macroTile('Fat', totalFat, const Color(0xFF8B8B8B)),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openCalorieCalculator,
              icon: const Icon(
                Icons.calculate_outlined,
                size: 18,
                color: Color(0xFF4D6A45),
              ),
              label: const Text(
                'Calculate Intake',
                style: TextStyle(
                  color: Color(0xFF4D6A45),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$mealCount meal entries logged today',
            style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String hint, {
    String? helper,
  }) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 1,
          filled: true,
          fillColor: const Color(0xFFF8FAF5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMealPhotoPreview() {
    final photoPath = _mealPhotoPath;
    if (photoPath == null || photoPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(photoPath),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 72,
                  height: 72,
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.photo, color: Colors.black45),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Meal photo ready. Add a food name and we will fill calories automatically.',
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _mealPhotoPath = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildMealTypeSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _mealTypes.map((mealType) {
        final isSelected = mealType == _selectedMealType;
        return ChoiceChip(
          label: Text(mealType),
          selected: isSelected,
          selectedColor: const Color(0xFF90A17D),
          backgroundColor: const Color(0xFFF8FAF5),
          side: BorderSide.none,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) {
            setState(() {
              _selectedMealType = mealType;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildWaterTracker({
    required int waterGlasses,
    required int waterGoal,
  }) {
    final progress = waterGoal <= 0 ? 0.0 : (waterGlasses / waterGoal).clamp(0, 1).toDouble();

    return Container(
      width: double.infinity,
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
          Row(
            children: [
              const Text(
                'Water Tracker',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$waterGlasses/$waterGoal glasses',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF69A9D5)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: waterGlasses <= 0 ? null : () => _setWaterGlasses(waterGlasses - 1),
                  icon: const Icon(Icons.remove),
                  label: const Text('Remove Glass'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _setWaterGlasses(waterGlasses + 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF69A9D5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.water_drop_outlined, color: Colors.white),
                  label: const Text(
                    'Add Glass',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSoftSection({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final weekStartKey = DateFormat('yyyy-MM-dd').format(weekStart);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Calories'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/todayIntake'),
            child: const Text(
              'Today',
              style: TextStyle(
                color: Color(0xFF90A17D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _dayRef.snapshots(),
        builder: (context, daySnapshot) {
          final dayData = daySnapshot.data?.data() ?? {};
          final currentGoal = (dayData['dailyGoal'] as num?)?.toInt() ?? _dailyGoal;
          final totalCalories = (dayData['totalCalories'] as num?)?.toInt() ?? 0;
          final totalProtein = (dayData['totalProtein'] as num?)?.toInt() ?? 0;
          final totalCarbs = (dayData['totalCarbs'] as num?)?.toInt() ?? 0;
          final totalFat = (dayData['totalFat'] as num?)?.toInt() ?? 0;
          final mealCount = (dayData['mealCount'] as num?)?.toInt() ?? 0;
          final waterGlasses = (dayData['waterGlasses'] as num?)?.toInt() ?? 0;
          final waterGoal = (dayData['waterGoal'] as num?)?.toInt() ?? _dailyWaterGoal;
          final progress = currentGoal <= 0
              ? 0.0
              : (totalCalories / currentGoal).clamp(0, 1).toDouble();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('users')
                .doc(_userId)
                .collection('calorie_logs')
                .orderBy(FieldPath.documentId, descending: true)
                .limit(14)
                .snapshots(),
            builder: (context, historySnapshot) {
              final dayDocs = historySnapshot.data?.docs ?? [];
              final weekDocs = dayDocs
                  .where((doc) => doc.id.compareTo(weekStartKey) >= 0)
                  .toList();
              final weeklyCalories = _weeklyTotal(weekDocs, 'totalCalories');
              final weeklyProtein = _weeklyTotal(weekDocs, 'totalProtein');
              final weeklyCarbs = _weeklyTotal(weekDocs, 'totalCarbs');
              final weeklyFat = _weeklyTotal(weekDocs, 'totalFat');

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDailyProgressCard(
                      totalCalories: totalCalories,
                      currentGoal: currentGoal,
                      totalCarbs: totalCarbs,
                      totalProtein: totalProtein,
                      totalFat: totalFat,
                      mealCount: mealCount,
                      progress: progress,
                    ),
                    const SizedBox(height: 18),
                    _buildWaterTracker(
                      waterGlasses: waterGlasses,
                      waterGoal: waterGoal,
                    ),
                    const SizedBox(height: 18),
                    _buildSoftSection(
                      title: 'Preset Foods',
                      trailing: TextButton(
                        onPressed: () {
                          setState(() {
                            _showPresetFoods = !_showPresetFoods;
                          });
                        },
                        child: Text(_showPresetFoods ? 'Hide' : 'Show'),
                      ),
                      child: _showPresetFoods
                          ? Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _presetFoods.map((preset) {
                                return ActionChip(
                                  label: Text(preset.name),
                                  onPressed: () => _applyPresetFood(preset),
                                );
                              }).toList(),
                            )
                          : const Text(
                              'Show quick picks for common foods and portion ideas.',
                              style: TextStyle(color: Colors.black54),
                            ),
                    ),
                    const SizedBox(height: 18),
                    _buildSoftSection(
                      title: 'Add Meal',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMealTypeSelector(),
                          const SizedBox(height: 12),
                          Autocomplete<_PresetFood>(
                            optionsBuilder: (textEditingValue) {
                              final query = textEditingValue.text.trim().toLowerCase();
                              if (query.isEmpty) {
                                return const Iterable<_PresetFood>.empty();
                              }
                              return _presetFoods.where(
                                (preset) => preset.name.toLowerCase().contains(query),
                              );
                            },
                            displayStringForOption: (option) => option.name,
                            onSelected: _applyPresetFood,
                            fieldViewBuilder: (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                onChanged: (value) {
                                  _mealController.value = textEditingController.value;
                                  _handleMealNameChanged(value);
                                },
                                  decoration: InputDecoration(
                                    hintText: 'Meal or snack',
                                    helperText:
                                      'Use food name plus quantity/unit below for better accuracy.',
                                    filled: true,
                                  fillColor: const Color(0xFFF8FAF5),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _quantityController,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (_) {
                                    _handleMealNameChanged(_mealController.text.trim());
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Quantity',
                                    helperText: 'Example: 2, 150, 0.5',
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAF5),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedMeasurementUnit,
                                  decoration: InputDecoration(
                                    labelText: 'Measurement',
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAF5),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  items: _measurementUnits.map((unit) {
                                    return DropdownMenuItem<String>(
                                      value: unit,
                                      child: Text(unit),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _selectedMeasurementUnit = value;
                                    });
                                    _handleMealNameChanged(_mealController.text.trim());
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (_isSearchingSuggestions)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            ),
                          if (_onlineSuggestions.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAF5),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Suggestions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ..._onlineSuggestions.map((suggestion) {
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(suggestion.displayName),
                                      subtitle: Text(
                                        suggestion.subtitle == null
                                            ? '${suggestion.calories} kcal'
                                            : '${suggestion.subtitle} - ${suggestion.calories} kcal',
                                      ),
                                      trailing: const Icon(Icons.north_west),
                                      onTap: () => _applyOnlineSuggestion(suggestion),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isLookingUpFood ? null : _scanBarcode,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Scan Barcode'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isCapturingMealPhoto || _isLookingUpFood
                                      ? null
                                      : _captureMealPhoto,
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: Text(
                                    _isCapturingMealPhoto
                                        ? 'Opening Camera...'
                                        : 'Camera Calorie',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _buildMealPhotoPreview(),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _numberField(
                                _calorieController,
                                'Calories',
                                helper: 'Example: 200 cal',
                              ),
                              const SizedBox(width: 10),
                              _numberField(
                                _proteinController,
                                'Protein',
                                helper: 'Example: 20 g',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _numberField(
                                _carbController,
                                'Carbs',
                                helper: 'Example: 30 g',
                              ),
                              const SizedBox(width: 10),
                              _numberField(
                                _fatController,
                                'Fat',
                                helper: 'Example: 10 g',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLookingUpFood ? null : _addMeal,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF90A17D),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: Text(
                                _isLookingUpFood ? 'Looking Up Food...' : 'Add Entry',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildSoftSection(
                      title: 'History',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAF5),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'This Week: $weeklyCalories kcal',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text('Protein: ${weeklyProtein}g'),
                                Text('Carbs: ${weeklyCarbs}g'),
                                Text('Fat: ${weeklyFat}g'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (dayDocs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('No calorie history yet.'),
                            )
                          else
                            ...dayDocs.map((doc) {
                              final data = doc.data();
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                color: const Color(0xFFF8FAF5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: ListTile(
                                  title: Text(doc.id),
                                  subtitle: Text(
                                    '${(data['totalCalories'] as num?)?.toInt() ?? 0} kcal - '
                                    'P ${(data['totalProtein'] as num?)?.toInt() ?? 0}g - '
                                    'C ${(data['totalCarbs'] as num?)?.toInt() ?? 0}g - '
                                    'F ${(data['totalFat'] as num?)?.toInt() ?? 0}g',
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PresetFood {
  const _PresetFood({
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

class _CalculatedFoodAmount {
  const _CalculatedFoodAmount({
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

class _NutritionLookupResult {
  const _NutritionLookupResult({
    required this.displayName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.subtitle,
  });

  final String displayName;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String? subtitle;
}

class _ArcProgressPainter extends CustomPainter {
  const _ArcProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final strokeWidth = size.width * 0.055;
    final segmentCount = 22;
    final gap = 0.06;
    const startAngle = 3.141592653589793;
    const sweepAngle = 3.141592653589793;
    final radius = size.width * 0.38;
    final center = Offset(size.width / 2, size.height * 0.84);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final segmentSweep = (sweepAngle - (segmentCount - 1) * gap) / segmentCount;
    final activeSegments = (segmentCount * clampedProgress).round();

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (var index = 0; index < segmentCount; index++) {
      final segmentStart = startAngle + index * (segmentSweep + gap);
      canvas.drawArc(
        rect,
        segmentStart,
        segmentSweep,
        false,
        index < activeSegments ? progressPaint : backgroundPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}
