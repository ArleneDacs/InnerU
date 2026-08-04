import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/services/api_config.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  // Every request in the app funnels through this client, and the
  // underlying `http` package has no default timeout -- a stalled or very
  // slow connection (weak signal, captive portal, dead Wi-Fi) leaves the
  // await hanging forever. That's most damaging at launch: main() awaits
  // AuthService.initialize(), which calls getJson('/api/me') before
  // runApp() ever fires, so a hung request here blocks the entire app from
  // rendering so much as the splash screen. Bounding every call here means
  // a slow network fails fast into the ApiException callers already catch,
  // instead of hanging indefinitely.
  static const Duration _defaultTimeout = Duration(seconds: 15);

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
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .get(_uri(path), headers: _headers(token: token))
        .timeout(timeout, onTimeout: _onTimeout);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .post(
          _uri(path),
          headers: _headers(token: token),
          body: jsonEncode(body),
        )
        .timeout(timeout, onTimeout: _onTimeout);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    String? token,
    Map<String, String>? fields,
    List<http.MultipartFile> files = const [],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers(token: token))
      ..fields.addAll(fields ?? {});
    request.files.addAll(files);

    // Uploads (photos/videos) legitimately take longer than a plain JSON
    // call, so this gets a longer bound rather than the default.
    final streamedResponse =
        await request.send().timeout(timeout, onTimeout: _onTimeout);
    final response = await http.Response.fromStream(streamedResponse);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .patch(
          _uri(path),
          headers: _headers(token: token),
          body: jsonEncode(body),
        )
        .timeout(timeout, onTimeout: _onTimeout);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? token,
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .delete(_uri(path), headers: _headers(token: token))
        .timeout(timeout, onTimeout: _onTimeout);
    return _decodeResponse(response);
  }

  Never _onTimeout() {
    throw const ApiTimeoutException();
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

/// Thrown when a request exceeds [ApiClient]'s bound instead of hanging
/// forever. Callers that already `catch (e)` broadly (nearly everywhere in
/// this app) handle this the same as any other network failure; code that
/// wants to react specifically to "request took too long" (e.g. to show a
/// slow-connection hint) can catch this type directly.
class ApiTimeoutException implements Exception {
  const ApiTimeoutException([
    this.message = 'The request took too long. Please check your connection and try again.',
  ]);

  final String message;

  @override
  String toString() => 'ApiTimeoutException: $message';
}
