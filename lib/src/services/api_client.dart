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
  // await hanging forever. That's especially damaging around session
  // validation and first-load data: although the shell now paints before
  // background startup work completes, a stalled request still prevents a
  // useful refresh or invalid-session decision. Bounding every call means a
  // slow network fails fast into the ApiException callers already catch.
  static const Duration _defaultTimeout = Duration(seconds: 15);

  void Function(String failedToken)? _onUnauthorized;

  /// AuthService registers a session invalidator here. Keeping the callback
  /// in the transport layer avoids a circular dependency while still making
  /// an expired bearer token log the user out no matter which API first sees
  /// the 401 response.
  void setUnauthorizedHandler(void Function(String failedToken)? handler) {
    _onUnauthorized = handler;
  }

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
    return _decodeResponse(
      response,
      requestToken: token,
    );
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
    return _decodeResponse(
      response,
      requestToken: token,
    );
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
    return _decodeResponse(
      response,
      requestToken: token,
    );
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
    return _decodeResponse(
      response,
      requestToken: token,
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    String? token,
    Duration timeout = _defaultTimeout,
  }) async {
    final response = await http
        .delete(_uri(path), headers: _headers(token: token))
        .timeout(timeout, onTimeout: _onTimeout);
    return _decodeResponse(
      response,
      requestToken: token,
    );
  }

  Never _onTimeout() {
    throw const ApiTimeoutException();
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required String? requestToken,
  }) {
    final raw = response.body.trim();
    final data = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data is Map<String, dynamic>
          ? data
          : <String, dynamic>{'data': data};
    }

    if (response.statusCode == 401 &&
        requestToken != null &&
        requestToken.isNotEmpty) {
      _onUnauthorized?.call(requestToken);
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
    this.message =
        'The request took too long. Please check your connection and try again.',
  ]);

  final String message;

  @override
  String toString() => 'ApiTimeoutException: $message';
}
