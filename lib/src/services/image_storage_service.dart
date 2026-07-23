import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/services/api_config.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class ImageStorageService {
  static bool get isConfigured =>
      AuthService.instance.currentSession?.token.isNotEmpty ?? false;
  static String? lastError;

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
      final host = parsed.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') {
        final base = Uri.parse(ApiConfig.baseUrl);
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
}
