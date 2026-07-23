import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class OllamaNutritionService {
  OllamaNutritionService._();

  static final OllamaNutritionService instance = OllamaNutritionService._();

  static const String _baseUrlFromDefine =
      String.fromEnvironment('OLLAMA_BASE_URL');
  static const String _modelFromDefine =
      String.fromEnvironment('OLLAMA_MODEL', defaultValue: 'llava');
  static const String _apiKeyFromDefine =
      String.fromEnvironment('OLLAMA_API_KEY');

  static String get baseUrl => _baseUrlFromDefine.isNotEmpty
      ? _baseUrlFromDefine
      : 'http://127.0.0.1:11434';

  static String get model => _modelFromDefine;
  static String get apiKey => _apiKeyFromDefine;

  // The 127.0.0.1 fallback above only ever resolves on a simulator running
  // on the same machine as a local Ollama server — on every real user's
  // phone it's unreachable. Without this check, isConfigured was true by
  // default (model has a non-empty default), so every unmatched food photo
  // silently burned a ~45s timeout in production before falling through.
  // Require an explicit OLLAMA_BASE_URL so that path is skipped entirely
  // unless a real, reachable endpoint has actually been deployed.
  static bool get isConfigured =>
      _baseUrlFromDefine.isNotEmpty && model.trim().isNotEmpty;

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
    };
  }

  Future<OllamaServiceStatus> checkStatus() async {
    if (!isConfigured) {
      return const OllamaServiceStatus(
        isReachable: false,
        message: 'AI assist is not configured.',
      );
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/tags'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return OllamaServiceStatus(
          isReachable: true,
          message: 'Ollama is ready for new food photos.',
        );
      }

      return OllamaServiceStatus(
        isReachable: false,
        message: 'Ollama responded with ${response.statusCode}.',
      );
    } on SocketException {
      return const OllamaServiceStatus(
        isReachable: false,
        message: 'Ollama could not be reached from this device.',
      );
    } on HttpException {
      return const OllamaServiceStatus(
        isReachable: false,
        message: 'Ollama rejected the connection.',
      );
    } on FormatException {
      return const OllamaServiceStatus(
        isReachable: false,
        message: 'Ollama returned an unexpected response.',
      );
    } catch (_) {
      return const OllamaServiceStatus(
        isReachable: false,
        message: 'Ollama is unavailable right now.',
      );
    }
  }

  Future<OllamaNutritionEstimate?> estimateNutritionFromImage({
    required String imagePath,
  }) async {
    if (!isConfigured) return null;

    final imageFile = File(imagePath);
    if (!await imageFile.exists()) return null;

    final imageBytes = await imageFile.readAsBytes();
    final imageBase64 = base64Encode(imageBytes);

    final uri = Uri.parse('$baseUrl/api/generate');
    final prompt = '''
You are a nutrition assistant.
Analyze this food image and identify the most likely food or meal.
Estimate a single realistic serving that best matches what is visible.
Return ONLY valid compact JSON with these keys:
meal_name, calories, protein, carbs, fat, confidence

Rules:
- meal_name must be a short, searchable food name in plain English
- prefer specific common names that could match a nutrition database
- if the food is packaged or branded, use the product name when obvious
- if multiple foods are visible, choose the main item in the portion
- calories, protein, carbs, fat must be numbers
- confidence must be a number from 0 to 1
- no markdown
- no explanation
''';

    final response = await http
        .post(
          uri,
          headers: _headers(),
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'images': [imageBase64],
            'stream': false,
            'format': 'json',
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception('Ollama request failed (${response.statusCode})');
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) return null;

    final rawResponse = payload['response'];
    if (rawResponse is! String || rawResponse.trim().isEmpty) return null;

    final parsed = jsonDecode(rawResponse);
    if (parsed is! Map<String, dynamic>) return null;

    final mealName = (parsed['meal_name'] as String?)?.trim();
    final calories = (parsed['calories'] as num?)?.toDouble();
    final protein = (parsed['protein'] as num?)?.toDouble();
    final carbs = (parsed['carbs'] as num?)?.toDouble();
    final fat = (parsed['fat'] as num?)?.toDouble();
    final confidence = (parsed['confidence'] as num?)?.toDouble() ?? 0;

    if (mealName == null || mealName.isEmpty) return null;
    if (calories == null || calories <= 0) return null;

    return OllamaNutritionEstimate(
      mealName: mealName,
      calories: calories.round(),
      protein: (protein ?? 0).round(),
      carbs: (carbs ?? 0).round(),
      fat: (fat ?? 0).round(),
      confidence: confidence,
    );
  }
}

class OllamaNutritionEstimate {
  const OllamaNutritionEstimate({
    required this.mealName,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.confidence,
  });

  final String mealName;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final double confidence;
}

class OllamaServiceStatus {
  const OllamaServiceStatus({
    required this.isReachable,
    required this.message,
  });

  final bool isReachable;
  final String message;
}
