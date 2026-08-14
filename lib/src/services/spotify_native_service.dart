import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spotify_sdk/models/connection_status.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:selfcare_projects/src/config/spotify_config.dart';

enum SpotifyNativeFailureReason {
  appNotInstalled,
  notLoggedIn,
  notAuthorized,
  offlineMode,
  unsupportedVersion,
  authenticationFailed,
  connectionFailed,
}

class SpotifyNativeException implements Exception {
  const SpotifyNativeException({
    required this.reason,
    required this.message,
    this.cause,
  });

  final SpotifyNativeFailureReason reason;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class SpotifyNativeService {
  SpotifyNativeService._();

  static final SpotifyNativeService instance = SpotifyNativeService._();

  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  bool _isConnected = false;
  String? _currentTrackUri;

  bool get isConnected => _isConnected;

  String get _scope => SpotifyConfig.scopes.join(',');

  bool get _usesRemoteAuthorizationFlow =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
        scope: _scope,
        playerName: 'InnerU',
      );
      _isConnected = connected;
      return connected;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spotify native connect failed: $error');
      }
      _isConnected = false;

      if (authorizeIfNeeded &&
          !_usesRemoteAuthorizationFlow &&
          _needsExplicitAuthorization(error)) {
        try {
          await authorize();
          return await connect(authorizeIfNeeded: false);
        } catch (authorizationError) {
          throw _toSpotifyException(authorizationError);
        }
      }

      throw _toSpotifyException(error);
    }
  }

  Future<void> authorize() async {
    try {
      final accessToken = await SpotifySdk.getAccessToken(
        clientId: SpotifyConfig.clientId,
        redirectUrl: SpotifyConfig.redirectUri,
        scope: _scope,
      );
      if (accessToken.trim().isEmpty) {
        throw const SpotifyNativeException(
          reason: SpotifyNativeFailureReason.authenticationFailed,
          message: 'Spotify did not return an authorization token.',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Spotify authorization failed: $error');
      }
      if (error is SpotifyNativeException) rethrow;
      throw _toSpotifyException(error);
    }
  }

  Future<bool> authorizeAndConnect() async {
    if (_usesRemoteAuthorizationFlow) {
      return connect(authorizeIfNeeded: false);
    }

    await authorize();
    return connect(authorizeIfNeeded: false);
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
        throw _toSpotifyException(error);
      }
      try {
        await SpotifySdk.play(spotifyUri: trackUri);
      } catch (retryError) {
        throw _toSpotifyException(retryError);
      }
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

  SpotifyNativeException _toSpotifyException(Object error) {
    if (error is SpotifyNativeException) return error;

    if (error is PlatformException) {
      switch (error.code) {
        case 'CouldNotFindSpotifyApp':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.appNotInstalled,
            message: 'Spotify is not installed on this device.',
            cause: error,
          );
        case 'NotLoggedInException':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.notLoggedIn,
            message: 'Please log in to the Spotify app, then try again.',
            cause: error,
          );
        case 'UserNotAuthorizedException':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.notAuthorized,
            message: 'Spotify needs permission before InnerU can play music.',
            cause: error,
          );
        case 'OfflineModeException':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.offlineMode,
            message: 'Spotify is in offline mode. Turn it off and try again.',
            cause: error,
          );
        case 'UnsupportedFeatureVersionException':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.unsupportedVersion,
            message: 'Please update Spotify, then try again.',
            cause: error,
          );
        case 'AuthenticationFailedException':
        case 'authenticationTokenError':
          return SpotifyNativeException(
            reason: SpotifyNativeFailureReason.authenticationFailed,
            message:
                'Spotify could not authorize InnerU. Please check Spotify and try again.',
            cause: error,
          );
      }

      final details = error.details?.toString().toLowerCase() ?? '';
      final message = error.message?.toLowerCase() ?? '';
      if (message.contains('not installed') ||
          details.contains('couldnotfindspotifyapp')) {
        return SpotifyNativeException(
          reason: SpotifyNativeFailureReason.appNotInstalled,
          message: 'Spotify is not installed on this device.',
          cause: error,
        );
      }
      if (message.contains('logged out') || details.contains('notloggedin')) {
        return SpotifyNativeException(
          reason: SpotifyNativeFailureReason.notLoggedIn,
          message: 'Please log in to the Spotify app, then try again.',
          cause: error,
        );
      }
      if (message.contains('authorize') || details.contains('notauthorize')) {
        return SpotifyNativeException(
          reason: SpotifyNativeFailureReason.notAuthorized,
          message: 'Spotify needs permission before InnerU can play music.',
          cause: error,
        );
      }
    }

    final text = error.toString().toLowerCase();
    if (text.contains('couldnotfindspotifyapp') ||
        text.contains('not installed')) {
      return SpotifyNativeException(
        reason: SpotifyNativeFailureReason.appNotInstalled,
        message: 'Spotify is not installed on this device.',
        cause: error,
      );
    }
    if (text.contains('notloggedin') || text.contains('logged out')) {
      return SpotifyNativeException(
        reason: SpotifyNativeFailureReason.notLoggedIn,
        message: 'Please log in to the Spotify app, then try again.',
        cause: error,
      );
    }
    if (text.contains('usernotauthorized') ||
        text.contains('authorization is required') ||
        text.contains('authorize')) {
      return SpotifyNativeException(
        reason: SpotifyNativeFailureReason.notAuthorized,
        message: 'Spotify needs permission before InnerU can play music.',
        cause: error,
      );
    }

    return SpotifyNativeException(
      reason: SpotifyNativeFailureReason.connectionFailed,
      message: 'Could not connect to Spotify. Please try again.',
      cause: error,
    );
  }
}
