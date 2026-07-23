import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/barcode_scanner_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/calorie_tracker/calorie_tracker_math.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/calorie_tracker_api_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/image_storage_service.dart';
import 'package:selfcare_projects/src/services/ollama_nutrition_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

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
      gramsPerUnit: 50.0,
    ),
    _PresetFood(
      name: 'Chicken Breast',
      calories: 165,
      protein: 31,
      carbs: 0,
      fat: 4,
      aliases: ['chicken breast', 'chicken'],
      defaultUnit: '100g',
      gramsPerUnit: 100.0,
    ),
    _PresetFood(
      name: 'White Rice',
      calories: 205,
      protein: 4,
      carbs: 45,
      fat: 0,
      aliases: ['white rice', 'rice'],
      defaultUnit: 'cup',
      gramsPerUnit: 158.0,
    ),
    _PresetFood(
      name: 'Banana',
      calories: 105,
      protein: 1,
      carbs: 27,
      fat: 0,
      aliases: ['banana', 'bananas'],
      defaultUnit: 'piece',
      gramsPerUnit: 118.0,
    ),
    _PresetFood(
      name: 'Apple',
      calories: 95,
      protein: 0,
      carbs: 25,
      fat: 0,
      aliases: ['apple', 'apples'],
      defaultUnit: 'piece',
      gramsPerUnit: 182.0,
    ),
    _PresetFood(
      name: 'Greek Yogurt',
      calories: 120,
      protein: 17,
      carbs: 7,
      fat: 2,
      aliases: ['greek yogurt', 'yogurt'],
      defaultUnit: 'cup',
      gramsPerUnit: 170.0,
    ),
    _PresetFood(
      name: 'Milk',
      calories: 103,
      protein: 8,
      carbs: 12,
      fat: 2,
      aliases: ['milk'],
      defaultUnit: '250ml',
      gramsPerUnit: 250.0,
    ),
    _PresetFood(
      name: 'Bread',
      calories: 80,
      protein: 3,
      carbs: 15,
      fat: 1,
      aliases: ['bread', 'toast'],
      defaultUnit: 'slice',
      gramsPerUnit: 30.0,
    ),
    _PresetFood(
      name: 'Peanut Butter',
      calories: 95,
      protein: 4,
      carbs: 3,
      fat: 8,
      aliases: ['peanut butter'],
      defaultUnit: 'tbsp',
      gramsPerUnit: 16.0,
    ),
    _PresetFood(
      name: 'Olive Oil',
      calories: 40,
      protein: 0,
      carbs: 0,
      fat: 5,
      aliases: ['olive oil'],
      defaultUnit: 'tsp',
      gramsPerUnit: 5.0,
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
  static const Map<String, String> _measurementUnitLabels = {
    'piece': 'pc',
    'g': 'g',
    'kg': 'kg',
    'oz': 'oz',
    'lb': 'lb',
    'ml': 'ml',
    'liter': 'l',
    'cup': 'cup',
    'tbsp': 'tbsp',
    'tsp': 'tsp',
    'slice': 'sl',
    'serving': 'srv',
  };

  final CalorieTrackerApiService _calorieApi =
      CalorieTrackerApiService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _mealController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _calorieController = TextEditingController();
  final TextEditingController _proteinController = TextEditingController();
  final TextEditingController _carbController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final FocusNode _mealFocusNode = FocusNode();

  Timer? _searchDebounce;
  Timer? _goalHintTimer;
  int _dailyGoal = 2000;
  final int _dailyWaterGoal = 8;
  Map<String, dynamic>? _todayDayData;
  List<Map<String, dynamic>> _historyDays = [];
  List<Map<String, dynamic>> _todayEntries = [];
  bool _isLoadingCalorieData = true;
  bool _isSavingGoal = false;
  bool _isLookingUpFood = false;
  bool _isSearchingSuggestions = false;
  bool _isCapturingMealPhoto = false;
  bool _isAnalyzingMealPhoto = false;
  bool _isCheckingOllamaStatus = false;
  bool _showPresetFoods = false;
  bool _showGoalHintBubble = false;
  bool? _isOllamaReachable;
  String _selectedMealType = 'Breakfast';
  String _selectedMeasurementUnit = 'piece';
  String _selectedHistoryDateKey = '';
  final GlobalKey _addMealSectionKey = GlobalKey();
  late DateTime _historyWeekStart;
  String? _mealPhotoPath;
  String _ollamaStatusMessage =
      'Saved foods are reused first. AI is only used for new foods.';
  List<_NutritionLookupResult> _onlineSuggestions = [];

  String get _todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get _sessionUserId =>
      AuthService.instance.currentUserId ?? AuthService.instance.currentSession?.id.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _selectedHistoryDateKey = _todayKey;
    _historyWeekStart = _startOfWeekSunday(DateTime.now());
    _loadCalorieData();
    _showGoalHint();
    _refreshOllamaStatus();
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

  Future<void> _scrollToSection(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) return;

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _openScanOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Quick Scan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you want to add food faster.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 18),
              _buildScanOptionTile(
                icon: Icons.camera_alt_rounded,
                title: 'Camera Calorie',
                subtitle: 'Take a photo and label the meal',
                onTap: () {
                  Navigator.pop(context);
                  _captureMealPhoto();
                },
              ),
              const SizedBox(height: 12),
              _buildScanOptionTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Barcode Scanner',
                subtitle: 'Scan packaged food details',
                onTap: () {
                  Navigator.pop(context);
                  _scanBarcode();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadCalorieData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingCalorieData = true;
    });

    try {
      final results = await Future.wait([
        _calorieApi.fetchDay(date: _todayKey),
        _calorieApi.fetchHistory(limit: 90),
      ]);

      if (!mounted) return;

      final dayResponse = results[0] as Map<String, dynamic>;
      final historyResponse = results[1] as List<Map<String, dynamic>>;
      final dayData = dayResponse['day'];
      final entries = dayResponse['entries'];
      final goal = (dayData is Map
              ? (dayData['dailyGoal'] as num?)?.toInt()
              : null) ??
          _dailyGoal;

      setState(() {
        _todayDayData = dayData is Map
            ? dayData.cast<String, dynamic>()
            : <String, dynamic>{};
        _todayEntries = entries is List
            ? entries
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList()
            : <Map<String, dynamic>>[];
        _historyDays = historyResponse;
        setState(() {
          _dailyGoal = goal;
        });
      });
    } catch (_) {
      if (mounted) {
        _showSnackBar('Could not load calorie data.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCalorieData = false;
        });
      }
    }
  }

  Future<void> _refreshOllamaStatus() async {
    if (_isCheckingOllamaStatus) return;

    setState(() {
      _isCheckingOllamaStatus = true;
    });

    try {
      final status = await OllamaNutritionService.instance.checkStatus();
      if (!mounted) return;
      setState(() {
        _isOllamaReachable = status.isReachable;
        _ollamaStatusMessage = status.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOllamaReachable = false;
        _ollamaStatusMessage =
            'Saved foods and regular nutrition lookup are still available.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingOllamaStatus = false;
        });
      }
    }
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
      final response = await _calorieApi.updateDay(
        date: _todayKey,
        dailyGoal: goal,
      );
      final day = response['day'];

      if (!mounted) return;
      setState(() {
        _dailyGoal = goal;
        if (day is Map) {
          _todayDayData = day.cast<String, dynamic>();
        }
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
    var goalText = (currentGoal > 0 ? currentGoal : _dailyGoal).toString();
    final parsedGoal = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Daily Calorie Goal'),
          content: TextFormField(
            initialValue: goalText,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (value) => goalText = value,
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
                int.tryParse(goalText.trim()),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (parsedGoal == null || !mounted) return;
    await _saveGoalValue(parsedGoal);
  }

  Future<void> _openCalorieCalculator() async {
    String selectedSex = 'Male';
    double activityMultiplier = 1.375;
    String activityLabel = 'Lightly active';
    var ageText = '';
    var weightText = '';
    var heightText = '';

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        String? validationMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void clearValidation() {
              if (validationMessage == null) return;
              setDialogState(() {
                validationMessage = null;
              });
            }

            return AlertDialog(
              title: const Text('Calorie Intake Calculator'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedSex,
                      decoration: const InputDecoration(labelText: 'Sex'),
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          selectedSex = value;
                          validationMessage = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: ageText,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        ageText = value;
                        clearValidation();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        hintText: 'Ex. 24',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: weightText,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        weightText = value;
                        clearValidation();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        hintText: 'Ex. 65',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: heightText,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        heightText = value;
                        clearValidation();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Height (cm)',
                        hintText: 'Ex. 170',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: activityLabel,
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
                          validationMessage = null;
                          activityMultiplier = switch (value) {
                            'Sedentary' => 1.2,
                            'Moderately active' => 1.55,
                            'Very active' => 1.725,
                            _ => 1.375,
                          };
                        });
                      },
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        validationMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                    final age = double.tryParse(ageText.trim());
                    final weight = double.tryParse(weightText.trim());
                    final height = double.tryParse(heightText.trim());

                    if (age == null ||
                        weight == null ||
                        height == null ||
                        age <= 0 ||
                        weight <= 0 ||
                        height <= 0) {
                      setDialogState(() {
                        validationMessage =
                            'Enter valid age, weight, and height.';
                      });
                      return;
                    }

                    final bmr = selectedSex == 'Male'
                        ? 10 * weight + 6.25 * height - 5 * age + 5
                        : 10 * weight + 6.25 * height - 5 * age - 161;
                    Navigator.pop(
                      context,
                      (bmr * activityMultiplier).round(),
                    );
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

    if (shouldUse != true || !mounted) return;
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
        _selectedMeasurementUnit = 'g';
      });

      final autoDetected = await _analyzeCapturedMealPhoto(image.path);
      if (!mounted || autoDetected) return;
      if (!autoDetected) {
        _showSnackBar(
          'Could not identify the food clearly. You can still edit the meal name manually.',
        );
      }
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

  Future<bool> _analyzeCapturedMealPhoto(String imagePath) async {
    if (_isAnalyzingMealPhoto) return false;

    setState(() {
      _isAnalyzingMealPhoto = true;
    });

    try {
      if (Platform.isIOS) {
        return await _tryAutofillMealFromFallbackImageAnalysis(imagePath);
      }

      final labeler = ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: 0.65),
      );

      try {
        final inputImage = InputImage.fromFilePath(imagePath);
        final labels = await labeler.processImage(inputImage);
        final detectedMealName = await _bestDetectedMealName(labels);
        if (!mounted || detectedMealName == null || detectedMealName.isEmpty) {
          return false;
        }

        _mealController.text = detectedMealName;
        _handleMealNameChanged(detectedMealName);
        final nutrition = await _ensureNutritionForMeal(detectedMealName);

        if (!mounted) return false;
        if (nutrition != null ||
            (int.tryParse(_calorieController.text.trim()) ?? 0) > 0) {
          final reusedSavedFood =
              nutrition?.subtitle == 'Saved from your previous logs';
          _showSnackBar(
            reusedSavedFood
                ? 'Matched $detectedMealName from your saved food history.'
                : 'Detected $detectedMealName and filled calories automatically.',
          );
          return true;
        }

        return false;
      } finally {
        await labeler.close();
      }
    } catch (error) {
      debugPrint('Meal photo analysis failed: $error');
      return await _tryAutofillMealFromFallbackImageAnalysis(imagePath);
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingMealPhoto = false;
        });
      }
    }
  }

  Future<String?> _bestDetectedMealName(List<ImageLabel> labels) async {
    if (labels.isEmpty) return null;

    const ignoredLabels = {
      'food',
      'dish',
      'cuisine',
      'ingredient',
      'tableware',
      'table',
      'recipe',
      'plate',
      'produce',
      'meal',
      'superfood',
    };

    final candidates = labels
        .map((label) => label.label.trim())
        .where((label) => label.isNotEmpty)
        .map((label) => label.toLowerCase())
        .where((label) => !ignoredLabels.contains(label))
        .toList();

    for (final candidate in candidates) {
      final cached = await _lookupFoodMemory(candidate);
      if (cached != null) {
        _applyOnlineSuggestion(cached);
        return cached.displayName;
      }
    }

    for (final candidate in candidates) {
      final preset = _findPresetFood(candidate);
      if (preset != null) {
        return preset.name;
      }
    }

    for (final candidate in candidates) {
      try {
        final suggestions = await _fetchOnlineSuggestions(candidate, limit: 1);
        if (suggestions.isNotEmpty) {
          return suggestions.first.displayName;
        }
      } catch (_) {
        // Keep trying other labels or fall back to manual input.
      }
    }

    final ollamaEstimate = await _estimateMealWithOllama(_mealPhotoPath);
    if (ollamaEstimate != null) {
      final result = await _nutritionResultFromDetectedMealName(
        ollamaEstimate.mealName,
        fallback: _nutritionResultFromOllamaEstimate(ollamaEstimate),
      );
      _applyOnlineSuggestion(result);
      await _saveFoodMemory(
        result.displayName,
        result,
        source: 'ollama_image_estimate',
      );
      return result.displayName;
    }

    return null;
  }

  Future<bool> _tryAutofillMealFromFallbackImageAnalysis(
      String imagePath) async {
    final ollamaEstimate = await _estimateMealWithOllama(imagePath);
    if (!mounted || ollamaEstimate == null) return false;

    final result = await _nutritionResultFromDetectedMealName(
      ollamaEstimate.mealName,
      fallback: _nutritionResultFromOllamaEstimate(ollamaEstimate),
    );
    _mealController.text = result.displayName;
    _handleMealNameChanged(result.displayName);
    _applyOnlineSuggestion(result);
    await _saveFoodMemory(
      result.displayName,
      result,
      source: 'ollama_image_estimate',
    );

    if (!mounted) return false;
    _showSnackBar(
      'Estimated ${result.displayName} from your photo and filled calories automatically.',
    );
    return true;
  }

  _NutritionLookupResult _nutritionResultFromOllamaEstimate(
    OllamaNutritionEstimate ollamaEstimate,
  ) {
    return _NutritionLookupResult(
      displayName: ollamaEstimate.mealName,
      calories: ollamaEstimate.calories,
      protein: ollamaEstimate.protein,
      carbs: ollamaEstimate.carbs,
      fat: ollamaEstimate.fat,
      subtitle: 'Estimated by local AI',
    );
  }

  Future<_NutritionLookupResult> _nutritionResultFromDetectedMealName(
    String mealName, {
    required _NutritionLookupResult fallback,
  }) async {
    final lookup = await _lookupNutritionForMealName(mealName);
    if (lookup != null) return lookup;
    return fallback;
  }

  Future<OllamaNutritionEstimate?> _estimateMealWithOllama(
    String? imagePath,
  ) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    try {
      return await OllamaNutritionService.instance.estimateNutritionFromImage(
        imagePath: imagePath,
      );
    } catch (error) {
      debugPrint('Ollama image estimate failed: $error');
      return null;
    }
  }

  Future<String?> _uploadMealPhotoIfNeeded() async {
      final photoPath = _mealPhotoPath;
    if (photoPath == null || photoPath.isEmpty) return null;
    if (!ImageStorageService.isConfigured) return null;

    try {
      final bytes = await File(photoPath).readAsBytes();
      return await ImageStorageService.uploadImageBytes(
        bytes,
        fileName:
            'meal_${_sessionUserId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (_) {
      return null;
    }
  }

  void _clearMealComposer() {
    if (!mounted) return;

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

  String _foodMemoryKey(String mealName) {
    return mealName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<_NutritionLookupResult?> _lookupFoodMemory(String mealName) async {
    final key = _foodMemoryKey(mealName);
    if (key.isEmpty) return null;

    try {
      final data = await _calorieApi.lookupFoodMemory(key);
      if (data == null) return null;

      final calories = (data['calories'] as num?)?.toInt();
      if (calories == null || calories <= 0) return null;

      return _NutritionLookupResult(
        displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : mealName,
        calories: calories,
        protein: (data['protein'] as num?)?.toInt() ?? 0,
        carbs: (data['carbs'] as num?)?.toInt() ?? 0,
        fat: (data['fat'] as num?)?.toInt() ?? 0,
        subtitle: 'Saved from your previous logs',
      );
    } catch (error) {
      debugPrint('Food memory lookup failed: $error');
      return null;
    }
  }

  Future<_NutritionLookupResult?> _lookupNutritionForMealName(
    String mealName,
  ) async {
    final cached = await _lookupFoodMemory(mealName);
    if (cached != null) return cached;

    final preset = _findPresetFood(mealName);
    if (preset != null) {
      return _NutritionLookupResult(
        displayName: preset.name,
        calories: preset.calories,
        protein: preset.protein,
        carbs: preset.carbs,
        fat: preset.fat,
        subtitle: 'Matched from your saved food presets',
      );
    }

    try {
      final suggestions = await _fetchOnlineSuggestions(mealName, limit: 1);
      if (suggestions.isNotEmpty) {
        return suggestions.first;
      }
    } catch (error) {
      debugPrint('Meal nutrition lookup failed: $error');
    }

    return null;
  }

  Future<void> _saveFoodMemory(
    String mealName,
    _NutritionLookupResult nutrition, {
    String source = 'manual',
  }) async {
    final key = _foodMemoryKey(mealName);
    if (key.isEmpty) return;

    try {
      await _calorieApi.upsertFoodMemory(
        key: key,
        displayName: nutrition.displayName,
        lookupName: mealName.trim(),
        calories: nutrition.calories,
        protein: nutrition.protein,
        carbs: nutrition.carbs,
        fat: nutrition.fat,
        source: source,
      );
    } catch (error) {
      debugPrint('Failed to save food memory: $error');
    }
  }

  Future<void> _addMeal() async {
    final mealName = _mealController.text.trim();
    if (mealName.isEmpty) {
      _showSnackBar('Enter a meal name first.');
      return;
    }

    final lookedUpNutrition = await _ensureNutritionForMeal(mealName);
    if (!mounted) return;

    final calories = int.tryParse(_calorieController.text.trim());
    final protein = int.tryParse(_proteinController.text.trim()) ?? 0;
    final carbs = int.tryParse(_carbController.text.trim()) ?? 0;
    final fat = int.tryParse(_fatController.text.trim()) ?? 0;
    final quantity = double.tryParse(_quantityController.text.trim());

    if (calories == null || calories <= 0) {
      _showSnackBar(
        lookedUpNutrition == null
            ? 'Could not detect calories automatically. Please enter them manually.'
            : 'Enter a valid calorie amount.',
      );
      return;
    }

    try {
      await _saveFoodMemory(
        mealName,
        _NutritionLookupResult(
          displayName: mealName,
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
        ),
        source: 'meal_log',
      );
      if (!mounted) return;

      final photoUrl = await _uploadMealPhotoIfNeeded();
      if (!mounted) return;

      final response = await _calorieApi.addEntry(
        date: _todayKey,
        meal: mealName,
        mealType: _selectedMealType,
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        quantity: quantity,
        measurementUnit: _selectedMeasurementUnit,
        photoUrl: photoUrl,
      );
      if (!mounted) return;

      final day = response['day'];
      final entries = response['entries'];
      setState(() {
        if (day is Map) {
          _todayDayData = day.cast<String, dynamic>();
          _dailyGoal = (day['dailyGoal'] as num?)?.toInt() ?? _dailyGoal;
        }
        _todayEntries = entries is List
            ? entries
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList()
            : _todayEntries;
      });

      _clearMealComposer();
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {
      _showSnackBar('Failed to add meal.');
    }
  }

  Future<void> _setWaterGlasses(int glasses) async {
    final clamped = glasses.clamp(0, _dailyWaterGoal);

    try {
      final response = await _calorieApi.updateDay(
        date: _todayKey,
        dailyGoal: _dailyGoal,
        waterGlasses: clamped,
        waterGoal: _dailyWaterGoal,
      );
      final day = response['day'];
      if (day is Map && mounted) {
        setState(() {
          _todayDayData = day.cast<String, dynamic>();
        });
      }
    } catch (_) {
      _showSnackBar('Failed to update water tracker.');
    }
  }

  void _applyPresetFood(_PresetFood preset) {
    if (!mounted) return;

    _mealController.text = preset.name;
    _calorieController.text = preset.calories.toString();
    _proteinController.text = preset.protein.toString();
    _carbController.text = preset.carbs.toString();
    _fatController.text = preset.fat.toString();
    setState(() {
      _selectedMeasurementUnit = _normalizeMeasurementUnit(preset.defaultUnit);
    });
  }

  void _applyFoodAmount(CalorieFoodAmount calculated) {
    if (!mounted) return;

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
    final preset = CalorieTrackerMath.findPresetFood(query, _presetFoods);
    if (preset == null) return null;
    return preset is _PresetFood ? preset : null;
  }

  String _normalizeMeasurementUnit(String rawUnit) {
    return CalorieTrackerMath.normalizeMeasurementUnit(rawUnit);
  }

  _CalculatedFoodAmount? _calculateFromMeasurement({
    required String mealName,
    required double quantity,
    required String unit,
  }) {
    final result = CalorieTrackerMath.calculateFromMeasurement(
      mealName: mealName,
      quantity: quantity,
      unit: unit,
      presets: _presetFoods,
    );
    if (result == null) return null;
    return _CalculatedFoodAmount(
      displayName: result.displayName,
      quantityLabel: result.quantityLabel,
      unit: result.unit,
      calories: result.calories,
      protein: result.protein,
      carbs: result.carbs,
      fat: result.fat,
    );
  }

  _CalculatedFoodAmount? _calculateFoodAmount(String query) {
    final result = CalorieTrackerMath.calculateFoodAmount(
      query: query,
      presets: _presetFoods,
    );
    if (result == null) return null;
    return _CalculatedFoodAmount(
      displayName: result.displayName,
      quantityLabel: result.quantityLabel,
      unit: result.unit,
      calories: result.calories,
      protein: result.protein,
      carbs: result.carbs,
      fat: result.fat,
    );
  }

  void _handleMealNameChanged(String value) {
    if (!mounted) return;

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

  Future<_NutritionLookupResult?> _ensureNutritionForMeal(
      String mealName) async {
    final existingCalories = int.tryParse(_calorieController.text.trim());
    if (existingCalories != null && existingCalories > 0) return null;

    final cached = await _lookupFoodMemory(mealName);
    if (!mounted) return null;
    if (cached != null) {
      _applyOnlineSuggestion(cached);
      return cached;
    }

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

    if (!mounted) return null;
    setState(() {
      _isLookingUpFood = true;
    });

    try {
      final suggestions = await _fetchOnlineSuggestions(mealName, limit: 1);
      if (!mounted) return null;
      if (suggestions.isEmpty) return null;
      final result = suggestions.first;
      _applyOnlineSuggestion(result);
      await _saveFoodMemory(mealName, result, source: 'online_lookup');
      return result;
    } on TimeoutException {
      _showSnackBar(
          'Food lookup timed out. You can still enter calories manually.');
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

  _NutritionLookupResult? _nutritionFromProductMap(
      Map<String, dynamic> product) {
    final nutriments = product['nutriments'];
    if (nutriments is! Map<String, dynamic>) return null;

    final servingCalories = _readDouble(nutriments['energy-kcal_serving']);
    final servingProtein = _readDouble(nutriments['proteins_serving']);
    final servingCarbs = _readDouble(nutriments['carbohydrates_serving']);
    final servingFat = _readDouble(nutriments['fat_serving']);
    final hundredCalories = _readDouble(nutriments['energy-kcal_100g']);
    final hundredProtein = _readDouble(nutriments['proteins_100g']);
    final hundredCarbs = _readDouble(nutriments['carbohydrates_100g']);
    final hundredFat = _readDouble(nutriments['fat_100g']);
    final fallbackCalories = _readDouble(nutriments['energy-kcal']);
    final servingGrams = _servingSizeInGrams(product['serving_size']);
    final servingMultiplier = servingGrams == null ? null : servingGrams / 100;

    final calculatedServingCalories =
        servingMultiplier == null || hundredCalories == null
            ? null
            : hundredCalories * servingMultiplier;
    final calculatedServingProtein =
        servingMultiplier == null || hundredProtein == null
            ? null
            : hundredProtein * servingMultiplier;
    final calculatedServingCarbs =
        servingMultiplier == null || hundredCarbs == null
            ? null
            : hundredCarbs * servingMultiplier;
    final calculatedServingFat = servingMultiplier == null || hundredFat == null
        ? null
        : hundredFat * servingMultiplier;

    final calories = servingCalories ??
        calculatedServingCalories ??
        hundredCalories ??
        fallbackCalories;
    if (calories == null || calories <= 0) return null;

    final productName = (product['product_name'] as String?)?.trim();
    final brands = (product['brands'] as String?)?.trim();
    final amountSuffix =
        servingCalories != null || calculatedServingCalories != null
            ? 'serving'
            : '100g';
    final displayName = productName == null || productName.isEmpty
        ? 'Food ($amountSuffix)'
        : '$productName ($amountSuffix)';

    return _NutritionLookupResult(
      displayName: displayName,
      calories: calories.round(),
      protein:
          (servingProtein ?? calculatedServingProtein ?? hundredProtein ?? 0)
              .round(),
      carbs:
          (servingCarbs ?? calculatedServingCarbs ?? hundredCarbs ?? 0).round(),
      fat: (servingFat ?? calculatedServingFat ?? hundredFat ?? 0).round(),
      subtitle: brands == null || brands.isEmpty ? null : brands,
    );
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }

  double? _servingSizeInGrams(dynamic servingSize) {
    if (servingSize is! String) return null;
    final match = RegExp(r'(\d+(?:[\.,]\d+)?)\s*(g|gram|grams|ml|mL)')
        .firstMatch(servingSize);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
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

    if (!mounted) return;
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
    if (!mounted) return;

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

    if (!mounted || barcode == null || barcode.isEmpty) return;

    setState(() {
      _isLookingUpFood = true;
    });

    try {
      final product = await _fetchBarcodeProduct(barcode);
      if (product == null) {
        _showSnackBar('Could not fetch barcode nutrition info.');
        return;
      }

      final result = _nutritionFromProductMap(product);
      if (result == null) {
        _showSnackBar('No nutrition data found for that barcode.');
        return;
      }

      if (!mounted) return;
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

  Future<Map<String, dynamic>?> _fetchBarcodeProduct(String rawBarcode) async {
    for (final barcode in _barcodeLookupCandidates(rawBarcode)) {
      final uri = Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/$barcode',
        {
          'fields': 'product_name,brands,serving_size,nutriments',
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'InnerU-SelfcareApp/1.0 (barcode food lookup)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) continue;

      final payload = json.decode(response.body);
      if (payload is! Map<String, dynamic>) continue;
      final product = payload['product'];
      if (product is Map<String, dynamic>) return product;
    }

    return null;
  }

  List<String> _barcodeLookupCandidates(String rawBarcode) {
    final digits = rawBarcode.replaceAll(RegExp(r'[^0-9]'), '');
    final candidates = <String>[];

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    add(rawBarcode);
    add(digits);
    if (digits.length == 12) add('0$digits');
    if (digits.length == 13 && digits.startsWith('0')) {
      add(digits.substring(1));
    }

    return candidates;
  }

  int _weeklyTotal(List<Map<String, dynamic>> docs, String key) {
    return docs.fold<int>(
      0,
      (total, doc) => total + ((doc[key] as num?)?.toInt() ?? 0),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  DateTime _startOfWeekSunday(DateTime date) {
    final offset = date.weekday % 7;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: offset));
  }

  String _historyWeekLabel(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    if (weekStart.month == weekEnd.month) {
      return '${DateFormat('MMMM').format(weekStart)} ${weekStart.year}';
    }
    if (weekStart.year == weekEnd.year) {
      return '${DateFormat('MMM').format(weekStart)} - ${DateFormat('MMM').format(weekEnd)} ${weekStart.year}';
    }
    return '${DateFormat('MMM yyyy').format(weekStart)} - ${DateFormat('MMM yyyy').format(weekEnd)}';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _goalHintTimer?.cancel();
    _mealController.dispose();
    _mealFocusNode.dispose();
    _quantityController.dispose();
    _calorieController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Widget _macroTile(String label, int grams, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.84),
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
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
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
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.24),
            theme.colorScheme.secondary.withValues(alpha: 0.28),
            theme.colorScheme.surface,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
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
              Text(
                'Daily Progress',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isSavingGoal
                    ? null
                    : () => _editGoalFromProgressCard(currentGoal),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(text: totalCalories.toString()),
                        TextSpan(
                          text: '/$goalLabel Kcal',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.58),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
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
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.14),
                      progressColor: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: theme.colorScheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totalCalories.toString(),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Calories',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 10,
                  bottom: 18,
                  child: Text(
                    '0%',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 18,
                  child: Text(
                    '$progressPercent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
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
              icon: Icon(
                Icons.calculate_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                'Calculate Intake',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$mealCount meal entries logged today',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCalendarStrip(List<Map<String, dynamic>> dayDocs) {
    final now = DateTime.now();
    final currentWeekStart = _startOfWeekSunday(now);
    final weekStart = _historyWeekStart;
    final canGoNext = weekStart.isBefore(currentWeekStart);
    final logsByDate = {
      for (final day in dayDocs) (day['date']?.toString() ?? ''): day,
    };
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.22 : 0.04,
            ),
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
                'History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  setState(() {
                    _historyWeekStart =
                        weekStart.subtract(const Duration(days: 7));
                  });
                },
                icon: const Icon(Icons.chevron_left_rounded),
                visualDensity: VisualDensity.compact,
                color: colorScheme.primary,
              ),
              Text(
                _historyWeekLabel(weekStart),
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: canGoNext
                    ? () {
                        setState(() {
                          _historyWeekStart =
                              weekStart.add(const Duration(days: 7));
                        });
                    }
                  : null,
                icon: const Icon(Icons.chevron_right_rounded),
                visualDensity: VisualDensity.compact,
                color: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(7, (index) {
              final date = weekStart.add(Duration(days: index));
              final key = DateFormat('yyyy-MM-dd').format(date);
              final isSelected = key == _selectedHistoryDateKey;
              final data = logsByDate[key];
              final dayCalories =
                  (data?['totalCalories'] as num?)?.toInt() ?? 0;
              final isToday = key == _todayKey;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedHistoryDateKey = key;
                      _historyWeekStart = _startOfWeekSunday(date);
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('E').format(date).substring(0, 3),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dayCalories > 0
                                ? colorScheme.primary
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(height: 6),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              maxWidth: 42,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Today',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayHistoryCard(Map<String, dynamic>? data) {
    final calories = (data?['totalCalories'] as num?)?.toInt() ?? 0;
    final protein = (data?['totalProtein'] as num?)?.toInt() ?? 0;
    final carbs = (data?['totalCarbs'] as num?)?.toInt() ?? 0;
    final fat = (data?['totalFat'] as num?)?.toInt() ?? 0;
    final water = (data?['waterGlasses'] as num?)?.toInt() ?? 0;
    final selectedDate =
        DateTime.tryParse(_selectedHistoryDateKey) ?? DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(selectedDate),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _historyMetricChip('$calories kcal', 'Calories'),
              _historyMetricChip('${protein}g', 'Protein'),
              _historyMetricChip('${carbs}g', 'Carbs'),
              _historyMetricChip('${fat}g', 'Fat'),
              _historyMetricChip('$water glasses', 'Water'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _historyMetricChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          children: [
            TextSpan(
              text: '$value\n',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    String? hint,
    String? suffix,
    String? previewSuffix,
  }) {
    final rawValue = controller.text.trim();
    final previewValue = rawValue.isEmpty
        ? null
        : previewSuffix == null || previewSuffix.isEmpty
            ? rawValue
            : '$rawValue $previewSuffix';
    final theme = Theme.of(context);

    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: (_) {
          if (!mounted) return;
          setState(() {});
        },
        decoration: _themedInputDecoration(
          theme: theme,
          labelText: label,
          hintText: hint ?? label,
          helperText: previewValue,
          suffixText: suffix,
        ),
      ),
    );
  }

  InputDecoration _themedInputDecoration({
    required ThemeData theme,
    required String labelText,
    String? hintText,
    String? helperText,
    String? suffixText,
  }) {
    final colorScheme = theme.colorScheme;
    final fillColor = theme.brightness == Brightness.dark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerHighest;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      helperMaxLines: helperText == null ? null : 1,
      suffixText: suffixText,
      filled: true,
      fillColor: fillColor,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(color: colorScheme.primary),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
      ),
      helperStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
      ),
      suffixStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    );
  }

  Widget _buildMealPhotoPreview() {
    final photoPath = _mealPhotoPath;
    if (photoPath == null || photoPath.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
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
                  color: colorScheme.surfaceContainer,
                  alignment: Alignment.center,
                  child: Icon(Icons.photo, color: colorScheme.onSurfaceVariant),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isAnalyzingMealPhoto
                  ? 'Analyzing your meal photo and filling calories...'
                  : 'Meal photo ready. We will auto-fill calories when the food is detected.',
              style: TextStyle(color: colorScheme.onSurface),
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

  Widget _buildCapturedMealFieldsHint() {
    if (_mealPhotoPath == null || _mealPhotoPath!.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Captured meal',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check the Food Name first, then enter the Grams so calories match the portion more accurately.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOllamaStatusBanner() {
    final bool isReady = _isOllamaReachable == true;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color tint = isReady
        ? colorScheme.primaryContainer.withValues(alpha: 0.85)
        : colorScheme.tertiaryContainer.withValues(alpha: 0.85);
    final Color iconColor =
        isReady ? colorScheme.primary : colorScheme.tertiary;
    final String title = _isCheckingOllamaStatus
        ? 'Checking AI calorie assist'
        : isReady
            ? 'AI calorie assist is ready'
            : 'Using saved foods and regular lookup';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isCheckingOllamaStatus
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(
                    isReady
                        ? Icons.auto_awesome_rounded
                        : Icons.inventory_2_outlined,
                    color: iconColor,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isCheckingOllamaStatus
                      ? 'Saved foods are reused first while we check the AI connection.'
                      : _ollamaStatusMessage,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (!_isCheckingOllamaStatus)
            IconButton(
              onPressed: _refreshOllamaStatus,
              tooltip: 'Refresh AI status',
              icon: const Icon(Icons.refresh_rounded),
              color: iconColor,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildMealTypeSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _mealTypes.map((mealType) {
        final isSelected = mealType == _selectedMealType;
        return ChoiceChip(
          label: Text(mealType),
          selected: isSelected,
          selectedColor:
              isDark ? colorScheme.primaryContainer : const Color(0xFF90A17D),
          backgroundColor: colorScheme.surfaceContainerHighest,
          side: BorderSide.none,
          labelStyle: TextStyle(
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
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
    final progress = waterGoal <= 0
        ? 0.0
        : (waterGlasses / waterGoal).clamp(0, 1).toDouble();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.12),
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
                'Water Tracker',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '$waterGlasses/$waterGoal glasses',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: colorScheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: waterGlasses <= 0
                      ? null
                      : () => _setWaterGlasses(waterGlasses - 1),
                  icon: const Icon(Icons.remove),
                  label: const Text('Remove Glass'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: waterGlasses >= waterGoal
                      ? null
                      : () => _setWaterGlasses(waterGlasses + 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(Icons.water_drop_outlined,
                      color: colorScheme.onPrimary),
                  label: Text(
                    'Add Glass',
                    style: TextStyle(color: colorScheme.onPrimary),
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
    Key? key,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.22 : 0.03,
            ),
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
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

  Widget _buildTodayEntriesCard(List<Map<String, dynamic>> entries) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalCalories = entries.fold<int>(
      0,
      (sum, item) => sum + ((item['calories'] as num?)?.toInt() ?? 0),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.22 : 0.03,
            ),
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
                'Today\'s Entries',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length} item${entries.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No meals logged yet today.',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Start with a quick scan or tap Log Food to add your first meal.',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _scrollToSection(_addMealSectionKey),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Log a meal'),
                ),
              ],
            )
          else ...[
            Text(
              '$totalCalories kcal logged today',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...entries.take(4).map((entry) {
              final meal =
                  (entry['meal'] as String?)?.trim().isNotEmpty == true
                      ? (entry['meal'] as String).trim()
                      : 'Meal';
              final mealType =
                  (entry['mealType'] as String?)?.trim().isNotEmpty == true
                      ? (entry['mealType'] as String).trim()
                      : 'Snack';
              final calories = (entry['calories'] as num?)?.toInt() ?? 0;
              final quantity = entry['quantity']?.toString().trim();
              final unit = (entry['measurementUnit'] as String?)?.trim();

              final quantityText = [
                if (quantity != null && quantity.isNotEmpty && quantity != 'null')
                  quantity,
                if (unit != null && unit.isNotEmpty) unit,
              ].join(' ').trim();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        mealType,
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (quantityText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              quantityText,
                              style: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.66),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$calories kcal',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (entries.length > 4)
              Text(
                '+${entries.length - 4} more logged items',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekStart =
        DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final weekStartKey = DateFormat('yyyy-MM-dd').format(weekStart);
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);

              return Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                appBar: AppBar(
                  backgroundColor: companyTheme.surfaceColor,
                  foregroundColor: companyTheme.inkColor,
                  iconTheme: IconThemeData(color: companyTheme.inkColor),
                  titleSpacing: 4,
                  title: Text(
                    'Food Calories',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: companyTheme.inkColor,
                    ),
                  ),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  actions: [
                    IconButton(
                      onPressed: _isLookingUpFood || _isCapturingMealPhoto
                          ? null
                          : _openScanOptions,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.iconTheme.color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.center_focus_weak_rounded),
                      tooltip: 'Quick scan',
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/todayIntake'),
                      icon: Icon(
                        Icons.calendar_month_rounded,
                        color: companyTheme.iconColor,
                        size: 18,
                      ),
                      label: Text(
                        'History',
                        style: TextStyle(
                          color: companyTheme.iconColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                body: _isLoadingCalorieData
                    ? const Center(child: CircularProgressIndicator())
                    : Builder(
                        builder: (context) {
                          final dayData = _todayDayData ?? {};
                          final currentGoal = (dayData['dailyGoal'] as num?)
                                  ?.toInt() ??
                              _dailyGoal;
                          final totalCalories =
                              (dayData['totalCalories'] as num?)?.toInt() ?? 0;
                          final totalProtein =
                              (dayData['totalProtein'] as num?)?.toInt() ?? 0;
                          final totalCarbs =
                              (dayData['totalCarbs'] as num?)?.toInt() ?? 0;
                          final totalFat =
                              (dayData['totalFat'] as num?)?.toInt() ?? 0;
                          final mealCount =
                              (dayData['mealCount'] as num?)?.toInt() ?? 0;
                          final waterGlasses =
                              (dayData['waterGlasses'] as num?)?.toInt() ?? 0;
                          final waterGoal =
                              (dayData['waterGoal'] as num?)?.toInt() ??
                                  _dailyWaterGoal;
                          final progress = currentGoal <= 0
                              ? 0.0
                              : (totalCalories / currentGoal)
                                  .clamp(0, 1)
                                  .toDouble();

                          final dayDocs = _historyDays;
                          final weekDocs = dayDocs
                              .where((doc) =>
                                  (doc['date']?.toString() ?? '')
                                      .compareTo(weekStartKey) >= 0)
                              .toList();
                          Map<String, dynamic>? selectedHistoryData;
                          for (final day in dayDocs) {
                            if (day['date']?.toString() ==
                                _selectedHistoryDateKey) {
                              selectedHistoryData = day;
                              break;
                            }
                          }
                          if (_selectedHistoryDateKey == _todayKey) {
                            selectedHistoryData = dayData;
                          }
                          final weeklyCalories =
                              _weeklyTotal(weekDocs, 'totalCalories');
                          final weeklyProtein =
                              _weeklyTotal(weekDocs, 'totalProtein');
                          final weeklyCarbs =
                              _weeklyTotal(weekDocs, 'totalCarbs');
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
                                _buildTodayEntriesCard(_todayEntries),
                                const SizedBox(height: 18),
                                _buildSoftSection(
                                  title: 'Preset Foods',
                                  trailing: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showPresetFoods = !_showPresetFoods;
                                      });
                                    },
                                    child: Text(
                                      _showPresetFoods ? 'Hide' : 'Show',
                                    ),
                                  ),
                                  child: _showPresetFoods
                                      ? Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: _presetFoods.map((preset) {
                                            return ActionChip(
                                              label: Text(preset.name),
                                              onPressed: () =>
                                                  _applyPresetFood(preset),
                                            );
                                          }).toList(),
                                        )
                                      : Text(
                                          'Show quick picks for common foods and portion ideas.',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.72),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 18),
                                _buildSoftSection(
                                  key: _addMealSectionKey,
                                  title: 'Add Meal',
                                  child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMealTypeSelector(),
                                    const SizedBox(height: 12),
                                    _buildCapturedMealFieldsHint(),
                                    RawAutocomplete<_PresetFood>(
                                      textEditingController: _mealController,
                                      focusNode: _mealFocusNode,
                                      optionsBuilder: (textEditingValue) {
                                        final query = textEditingValue.text
                                            .trim()
                                            .toLowerCase();
                                        if (query.isEmpty) {
                                          return const Iterable<
                                              _PresetFood>.empty();
                                        }
                                        return _presetFoods.where(
                                          (preset) => preset.name
                                              .toLowerCase()
                                              .contains(query),
                                        );
                                      },
                                      displayStringForOption: (option) =>
                                          option.name,
                                      onSelected: _applyPresetFood,
                                      optionsViewBuilder:
                                          (context, onSelected, options) {
                                        final popupTheme = Theme.of(context);
                                        final popupColors =
                                            popupTheme.colorScheme;
                                        return Align(
                                          alignment: Alignment.topLeft,
                                          child: Material(
                                            elevation: 4,
                                            color: popupColors.surface,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxHeight: 220,
                                                maxWidth: 360,
                                              ),
                                              child: ListView.builder(
                                                padding: EdgeInsets.zero,
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                itemBuilder: (context, index) {
                                                  final option =
                                                      options.elementAt(index);
                                                  return ListTile(
                                                    title: Text(
                                                      option.name,
                                                      style: TextStyle(
                                                        color: popupColors
                                                            .onSurface,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      '${option.calories} kcal',
                                                      style: TextStyle(
                                                        color: popupColors
                                                            .onSurface
                                                            .withValues(
                                                                alpha: 0.72),
                                                      ),
                                                    ),
                                                    onTap: () =>
                                                        onSelected(option),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                      },
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
                                            _handleMealNameChanged(value);
                                          },
                                          decoration: _themedInputDecoration(
                                            theme: theme,
                                            labelText: 'Food Name',
                                            hintText: _mealPhotoPath == null
                                                ? 'Meal or snack'
                                                : 'Detected food name',
                                            helperText: _mealPhotoPath == null
                                                ? 'Use food name plus quantity/unit below for better accuracy.'
                                                : 'Review the detected food name before saving.',
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
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            onChanged: (_) {
                                              _handleMealNameChanged(
                                                  _mealController.text.trim());
                                            },
                                            decoration: _themedInputDecoration(
                                              theme: theme,
                                              labelText: 'Quantity',
                                              hintText: 'Enter amount',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child:
                                              DropdownButtonFormField<String>(
                                            initialValue:
                                                _selectedMeasurementUnit,
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface,
                                            ),
                                            dropdownColor:
                                                theme.colorScheme.surface,
                                            decoration: _themedInputDecoration(
                                              theme: theme,
                                              labelText: _mealPhotoPath == null
                                                  ? 'Measurement'
                                                  : 'Unit',
                                            ),
                                            items:
                                                _measurementUnits.map((unit) {
                                              return DropdownMenuItem<String>(
                                                value: unit,
                                                child: Text(
                                                  _measurementUnitLabels[
                                                          unit] ??
                                                      unit,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              if (value == null) return;
                                              setState(() {
                                                _selectedMeasurementUnit =
                                                    value;
                                              });
                                              _handleMealNameChanged(
                                                  _mealController.text.trim());
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_isSearchingSuggestions)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: LinearProgressIndicator(
                                            minHeight: 3),
                                      ),
                                    if (_onlineSuggestions.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Suggestions',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: theme
                                                    .colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ..._onlineSuggestions
                                                .map((suggestion) {
                                              return ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                  suggestion.displayName,
                                                  style: TextStyle(
                                                    color: theme.colorScheme
                                                        .onSurface,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  suggestion.subtitle == null
                                                      ? '${suggestion.calories} kcal'
                                                      : '${suggestion.subtitle} - ${suggestion.calories} kcal',
                                                  style: TextStyle(
                                                    color: theme.colorScheme
                                                        .onSurface
                                                        .withValues(
                                                            alpha: 0.72),
                                                  ),
                                                ),
                                                trailing: Icon(
                                                  Icons.north_west,
                                                  color: theme.colorScheme
                                                      .primary,
                                                ),
                                                onTap: () =>
                                                    _applyOnlineSuggestion(
                                                        suggestion),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    _buildOllamaStatusBanner(),
                                    const SizedBox(height: 12),
                                    Material(
                                      color: theme.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(22),
                                      child: InkWell(
                                        onTap: _isLookingUpFood ||
                                                _isCapturingMealPhoto
                                            ? null
                                            : _openScanOptions,
                                        borderRadius: BorderRadius.circular(22),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme
                                                      .primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Icon(
                                                  Icons
                                                      .center_focus_weak_rounded,
                                                  color: theme.colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Quick Scan',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: theme
                                                            .colorScheme.onSurface,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Open camera or barcode scanner',
                                                      style: TextStyle(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha: 0.72),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _isCapturingMealPhoto
                                                    ? 'Opening...'
                                                    : _isLookingUpFood
                                                        ? 'Loading...'
                                                        : 'Open',
                                                style: TextStyle(
                                                  color: theme.colorScheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    _buildMealPhotoPreview(),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _numberField(
                                          _calorieController,
                                          'Calories',
                                          hint: '200',
                                          suffix: 'cal',
                                          previewSuffix: 'cal',
                                        ),
                                        const SizedBox(width: 10),
                                        _numberField(
                                          _proteinController,
                                          'Protein',
                                          hint: '20',
                                          suffix: 'g',
                                          previewSuffix: 'g protein',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _numberField(
                                          _carbController,
                                          'Carbs',
                                          hint: '30',
                                          suffix: 'g',
                                          previewSuffix: 'g carbs',
                                        ),
                                        const SizedBox(width: 10),
                                        _numberField(
                                          _fatController,
                                          'Fat',
                                          hint: '10',
                                          suffix: 'g',
                                          previewSuffix: 'g fat',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed:
                                            _isLookingUpFood ? null : _addMeal,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              theme.colorScheme.primary,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 15),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                        child: Text(
                                          _isLookingUpFood
                                              ? 'Looking Up Food...'
                                              : 'Add Entry',
                                          style: TextStyle(
                                            color: theme.colorScheme.onPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
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
                                    _buildHistoryCalendarStrip(dayDocs),
                                    const SizedBox(height: 18),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'This Week: $weeklyCalories kcal',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Protein: ${weeklyProtein}g',
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.72),
                                            ),
                                          ),
                                          Text(
                                            'Carbs: ${weeklyCarbs}g',
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.72),
                                            ),
                                          ),
                                          Text(
                                            'Fat: ${weeklyFat}g',
                                            style: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.72),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    _buildSoftSection(
                                      title: 'Selected Day',
                                      child: _buildSelectedDayHistoryCard(
                                          selectedHistoryData),
                                    ),
                                    const SizedBox(height: 12),
                                    if (dayDocs.isEmpty)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text('No calorie history yet.'),
                                      )
                                    else
                                      ...dayDocs.map((day) {
                                        final dateKey =
                                            day['date']?.toString() ?? '';
                                        return Card(
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          elevation: 0,
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          child: ListTile(
                                            title: Text(
                                              dateKey,
                                              style: TextStyle(
                                                color:
                                                    theme.colorScheme.onSurface,
                                              ),
                                            ),
                                            subtitle: Text(
                                              '${(day['totalCalories'] as num?)?.toInt() ?? 0} kcal - '
                                              'P ${(day['totalProtein'] as num?)?.toInt() ?? 0}g - '
                                              'C ${(day['totalCarbs'] as num?)?.toInt() ?? 0}g - '
                                              'F ${(day['totalFat'] as num?)?.toInt() ?? 0}g',
                                              style: TextStyle(
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.72),
                                              ),
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
                      ),
                );
              },
            ),
          );
        },
      );
  }
}

class _PresetFood extends CalorieFoodPreset {
  const _PresetFood({
    required super.name,
    required super.calories,
    required super.protein,
    required super.carbs,
    required super.fat,
    required super.aliases,
    required super.defaultUnit,
    required super.gramsPerUnit,
  });
}

class _CalculatedFoodAmount extends CalorieFoodAmount {
  const _CalculatedFoodAmount({
    required super.displayName,
    required super.quantityLabel,
    required super.unit,
    required super.calories,
    required super.protein,
    required super.carbs,
    required super.fat,
  });
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
