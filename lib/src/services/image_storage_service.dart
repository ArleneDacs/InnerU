import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/config/cloudinary_config.dart';

class ImageStorageService {
  static const String _cloudNameFromDefine =
      String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const String _uploadPresetFromDefine =
      String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

  static String get cloudName => _cloudNameFromDefine.isNotEmpty
      ? _cloudNameFromDefine
      : CloudinaryConfig.cloudName;
  static String get uploadPreset => _uploadPresetFromDefine.isNotEmpty
      ? _uploadPresetFromDefine
      : CloudinaryConfig.uploadPreset;

  static bool get isConfigured =>
      cloudName.isNotEmpty && uploadPreset.isNotEmpty;
  static String? lastError;

  static Uri get _uploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  static Future<String?> uploadImageBytes(
    Uint8List bytes, {
    String fileName = 'upload.jpg',
  }) async {
    lastError = null;
    if (!isConfigured) {
      lastError =
          'Cloudinary is not configured. Missing cloud/preset. cloud="$cloudName" preset="$uploadPreset"';
      print(lastError);
      return null;
    }

    try {
      final request = http.MultipartRequest('POST', _uploadUri)
        ..fields['upload_preset'] = uploadPreset
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
        String message = 'Cloudinary upload failed (${response.statusCode}).';
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final error = data['error'];
          if (error is Map<String, dynamic> && error['message'] != null) {
            message = error['message'].toString();
          }
        } catch (_) {}
        message =
            '$message (cloud="$cloudName", preset="$uploadPreset")';
        lastError = message;
        print('Cloudinary upload failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    } catch (e) {
      lastError = e.toString();
      print('Cloudinary upload error: $e');
      return null;
    }
  }

  static Future<String?> uploadImageFile(File file) async {
    final bytes = await file.readAsBytes();
    return uploadImageBytes(bytes, fileName: file.uri.pathSegments.last);
  }
}
