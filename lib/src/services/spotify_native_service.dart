import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spotify_sdk/models/connection_status.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:selfcare_projects/src/config/spotify_config.dart';

class SpotifyNativeService {
  SpotifyNativeService._();

  static final SpotifyNativeService instance = SpotifyNativeService._();

  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  bool _isConnected = false;
  String? _currentTrackUri;

  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    _connectionSubscription ??=
        SpotifySdk.subscribeConnectionStatus().listen((status) {
          _isConnected = status.connected;
        });
  }

  Future<bool> connect({bool authorizeIfNeeded = true}) async {
    await initialize();

    try {
      if (_isConnected) {
        return true;
      }

      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: SpotifyConfig.clientId,
        redirectUrl: SpotifyConfig.redirectUri,
      );
      _isConnected = connected;
      return connected;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spotify native connect failed: $error');
      }
      _isConnected = false;

      if (authorizeIfNeeded && _needsExplicitAuthorization(error)) {
        await authorize();
        return connect(authorizeIfNeeded: false);
      }

      rethrow;
    }
  }

  Future<void> authorize() async {
    try {
      await SpotifySdk.getAccessToken(
        clientId: SpotifyConfig.clientId,
        redirectUrl: SpotifyConfig.redirectUri,
        scope: SpotifyConfig.scopes.join(','),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spotify authorization failed: $error');
      }
      rethrow;
    }
  }

  bool _needsExplicitAuthorization(Object error) {
    if (error is PlatformException) {
      return error.code == 'UserNotAuthorizedException' ||
          (error.message?.toLowerCase().contains('authorization') ?? false);
    }

    return error.toString().contains('UserNotAuthorizedException') ||
        error.toString().toLowerCase().contains('authorization is required');
  }

  Future<void> playTrack(String trackUri) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) {
        throw Exception('Could not connect to Spotify.');
      }
    }

    _currentTrackUri = trackUri;
    try {
      await SpotifySdk.play(spotifyUri: trackUri);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spotify native play failed, reconnecting once: $error');
      }
      _isConnected = false;
      final connected = await connect();
      if (!connected) {
        rethrow;
      }
      await SpotifySdk.play(spotifyUri: trackUri);
    }
  }

  Future<void> pause() async {
    if (!_isConnected) return;
    await SpotifySdk.pause();
  }

  Future<void> resume() async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) {
        throw Exception('Could not connect to Spotify.');
      }
    }

    if (_currentTrackUri != null) {
      await SpotifySdk.resume();
    }
  }

  Future<void> stop() async {
    if (!_isConnected) return;
    await SpotifySdk.pause();
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: 0);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    try {
      await SpotifySdk.disconnect();
    } catch (_) {}
    _isConnected = false;
  }

  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await disconnect();
  }
}
