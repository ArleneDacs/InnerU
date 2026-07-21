import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/services/api_config.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  Map<String, String> _headers({String? token}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? token,
  }) async {
    final response = await http.get(_uri(path), headers: _headers(token: token));
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http.post(
      _uri(path),
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile> files = const [],
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers(token: token))
      ..fields.addAll(fields ?? {});
    request.files.addAll(files);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http.patch(
      _uri(path),
      headers: _headers(token: token),
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? token,
  }) async {
    final response =
        await http.delete(_uri(path), headers: _headers(token: token));
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final raw = response.body.trim();
    final data = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data is Map<String, dynamic>
          ? data
          : <String, dynamic>{'data': data};
    }

    if (data is Map<String, dynamic>) {
      throw ApiException(
        response.statusCode,
        data['message']?.toString() ?? 'Request failed.',
        errors: data['errors'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['errors'] as Map)
            : null,
      );
    }

    throw ApiException(response.statusCode, 'Request failed.');
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.errors});

  final int statusCode;
  final String message;
  final Map<String, dynamic>? errors;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
