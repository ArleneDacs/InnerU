import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/services/api_config.dart';
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class ImageStorageService {
  static bool get isConfigured =>
      AuthService.instance.currentSession?.token.isNotEmpty ?? false;
  static String? lastError;

  static Uri _normalizedApiBase() => Uri.parse(ApiConfig.baseUrl);

  static Future<String?> uploadImageBytes(
    Uint8List bytes, {
    String fileName = 'upload.jpg',
  }) async {
    return _uploadBytes(
      bytes,
      fileName: fileName,
      kind: 'avatar',
    );
  }

  static Future<String?> uploadCommunityImageBytes(
    Uint8List bytes, {
    String fileName = 'community.jpg',
  }) async {
    return _uploadBytes(
      bytes,
      fileName: fileName,
      kind: 'community',
    );
  }

  static Future<String?> uploadStepProofBytes(
    Uint8List bytes, {
    String fileName = 'step-proof.jpg',
  }) async {
    return _uploadBytes(
      bytes,
      fileName: fileName,
      kind: 'step_proof',
    );
  }

  /// Uploads a photo only after the Exercise queue has safely persisted its
  /// original bytes. The deterministic file name is supplied by the queue so
  /// a timeout/retry cannot create an unbounded set of duplicate uploads.
  static Future<String?> uploadExerciseImageBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    lastError = null;
    final session = AuthService.instance.currentSession;
    if (session == null || session.token.isEmpty) {
      lastError = 'Media upload requires a signed-in session.';
      return null;
    }

    try {
      final response = await ApiClient.instance.postMultipart(
        '/api/media/upload',
        token: session.token,
        fields: const <String, String>{'kind': 'exercise'},
        files: <http.MultipartFile>[
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        ],
      );
      final url = response['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        lastError = 'Media upload did not return a photo URL.';
        return null;
      }
      return url;
    } catch (error) {
      lastError = error.toString();
      return null;
    }
  }

  static Future<String?> uploadGroupPhotoBytes(
    Uint8List bytes, {
    String fileName = 'group-photo.jpg',
  }) async {
    return _uploadBytes(
      bytes,
      fileName: fileName,
      kind: 'group_photo',
    );
  }

  static Future<String?> uploadVideoFile(File file) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(
      bytes,
      fileName: file.uri.pathSegments.last,
      kind: 'video',
    );
  }

  static Future<String?> uploadVideoBytes(
    Uint8List bytes, {
    String fileName = 'loading-video.mp4',
  }) async {
    return _uploadBytes(
      bytes,
      fileName: fileName,
      kind: 'video',
    );
  }

  static Future<String?> _uploadBytes(
    Uint8List bytes, {
    required String fileName,
    required String kind,
  }) async {
    lastError = null;
    if (!isConfigured) {
      lastError = 'Media upload is not configured. Sign in first.';
      print(lastError);
      return null;
    }

    try {
      final session = AuthService.instance.currentSession;
      if (session == null) {
        lastError = 'Media upload requires a signed-in session.';
        return null;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/media/upload'),
      )
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${session.token}'
        ..fields['kind'] = kind
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      print('Media upload response: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        String message = 'Media upload failed (${response.statusCode}).';
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final error = data['message'];
          if (error != null) {
            message = error.toString();
          }
        } catch (_) {}
        lastError = message;
        print('Media upload failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['url'] as String? ?? data['profile_pic'] as String?;
    } catch (e) {
      lastError = e.toString();
      print('Media upload error: $e');
      return null;
    }
  }

  static Future<String?> uploadImageFile(File file) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(
      bytes,
      fileName: file.uri.pathSegments.last,
      kind: 'avatar',
    );
  }

  static Future<String?> uploadCommunityImageFile(File file) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(
      bytes,
      fileName: file.uri.pathSegments.last,
      kind: 'community',
    );
  }

  static String normalizeMediaUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw == 'loading') return raw;
    if (raw.startsWith('data:')) return raw;

    final parsed = Uri.tryParse(raw);
    if (parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      final base = _normalizedApiBase();
      final host = parsed.host.toLowerCase();
      final baseHost = base.host.toLowerCase();
      final shouldRewrite =
          host == 'localhost' || host == '127.0.0.1' || host == baseHost;
      if (shouldRewrite) {
        final normalized = base.replace(
          path: parsed.path,
          queryParameters: parsed.hasQuery ? parsed.queryParameters : null,
        );
        if (parsed.fragment.isEmpty) {
          return normalized.toString();
        }
        return normalized.replace(fragment: parsed.fragment).toString();
      }
      return raw;
    }

    if (raw.startsWith('//')) {
      return 'https:$raw';
    }

    if (raw.startsWith('/')) {
      return '${ApiConfig.baseUrl}$raw';
    }

    return '${ApiConfig.baseUrl}/${raw.replaceAll(RegExp(r'^/+'), '')}';
  }

  static String normalizeCommunityMediaUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw == 'loading') return raw;
    if (raw.startsWith('data:')) return raw;

    final parsed = Uri.tryParse(raw);
    if (parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      final base = _normalizedApiBase();
      final host = parsed.host.toLowerCase();
      final baseHost = base.host.toLowerCase();
      final shouldRewrite =
          host == 'localhost' || host == '127.0.0.1' || host == baseHost;
      if (shouldRewrite) {
        final normalized = base.replace(
          path: parsed.path,
          queryParameters: parsed.hasQuery ? parsed.queryParameters : null,
        );
        if (parsed.fragment.isEmpty) {
          return normalized.toString();
        }
        return normalized.replace(fragment: parsed.fragment).toString();
      }
      return raw;
    }

    if (raw.startsWith('//')) {
      return 'https:$raw';
    }

    final cleanedPath = raw.replaceAll(RegExp(r'^/+'), '');
    if (cleanedPath.isEmpty) return '';

    if (cleanedPath.startsWith('storage/')) {
      return '${ApiConfig.baseUrl}/$cleanedPath';
    }

    return '${ApiConfig.baseUrl}/storage/$cleanedPath';
  }
}
