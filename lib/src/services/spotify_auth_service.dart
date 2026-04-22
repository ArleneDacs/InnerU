import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/config/spotify_config.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyAuthService {
  SpotifyAuthService._();

  static final SpotifyAuthService instance = SpotifyAuthService._();

  final AppLinks _appLinks = AppLinks();

  String? _accessToken;
  DateTime? _expiry;

  bool get isConnected =>
      _accessToken != null &&
      _expiry != null &&
      DateTime.now().isBefore(_expiry!);

  Future<String?> getAccessToken({bool promptIfNeeded = false}) async {
    if (isConnected) {
      return _accessToken;
    }

    if (!promptIfNeeded) {
      return null;
    }

    return authenticate();
  }

  Future<String> authenticate() async {
    final verifier = _generateCodeVerifier();
    final challenge = _codeChallengeForVerifier(verifier);
    final state = _randomString(24);

    final authUri = Uri.https(
      'accounts.spotify.com',
      '/authorize',
      {
        'client_id': SpotifyConfig.clientId,
        'response_type': 'code',
        'redirect_uri': SpotifyConfig.redirectUri,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': SpotifyConfig.scopes.join(' '),
      },
    );

    final linkFuture = _waitForRedirect(state);
    final launched = await launchUrl(
      authUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw Exception('Could not open Spotify login.');
    }

    final callbackUri = await linkFuture.timeout(
      const Duration(minutes: 3),
    );

    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('Spotify login did not return an authorization code.');
    }

    return _exchangeCodeForToken(
      code: code,
      verifier: verifier,
    );
  }

  Future<Uri> _waitForRedirect(String expectedState) async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (_isMatchingSpotifyRedirect(initialLink, expectedState)) {
        return initialLink!;
      }
    } catch (_) {}

    final completer = Completer<Uri>();
    late final StreamSubscription<Uri> subscription;
    subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        if (_isMatchingSpotifyRedirect(uri, expectedState) &&
            !completer.isCompleted) {
          completer.complete(uri);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  bool _isMatchingSpotifyRedirect(Uri? uri, String expectedState) {
    if (uri == null) return false;
    final redirect = Uri.parse(SpotifyConfig.redirectUri);
    if (uri.scheme != redirect.scheme || uri.host != redirect.host) {
      return false;
    }
    if (uri.queryParameters['state'] != expectedState) {
      return false;
    }
    return uri.queryParameters.containsKey('code');
  }

  Future<String> _exchangeCodeForToken({
    required String code,
    required String verifier,
  }) async {
    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': SpotifyConfig.clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': SpotifyConfig.redirectUri,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Spotify token exchange failed.');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['access_token'] as String?;
    final expiresIn = (payload['expires_in'] as num?)?.toInt() ?? 3600;
    if (token == null || token.isEmpty) {
      throw Exception('Spotify access token is missing.');
    }

    _accessToken = token;
    _expiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    return token;
  }

  String _generateCodeVerifier() => _randomString(96);

  String _codeChallengeForVerifier(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _randomString(int length) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
