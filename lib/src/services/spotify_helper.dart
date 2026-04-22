import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:selfcare_projects/src/config/spotify_config.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyTrack {
  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artistNames,
    required this.spotifyUrl,
    required this.albumImageUrl,
  });

  final String id;
  final String title;
  final String artistNames;
  final String spotifyUrl;
  final String albumImageUrl;

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List<dynamic>? ?? const [])
        .map((artist) => (artist as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    final images =
        ((json['album'] as Map<String, dynamic>?)?['images'] as List<dynamic>? ??
            const []);

    return SpotifyTrack(
      id: (json['id'] as String?) ?? '',
      title: (json['name'] as String?) ?? 'Spotify track',
      artistNames: artists.isEmpty ? 'Unknown artist' : artists,
      spotifyUrl:
          ((json['external_urls'] as Map<String, dynamic>?)?['spotify'] as String?) ??
              '',
      albumImageUrl: images.isNotEmpty
          ? ((images.first as Map<String, dynamic>)['url'] as String? ?? '')
          : '',
    );
  }
}

class SpotifyHelper {
  static const List<String> suggestedSearchTerms = [
    'relaxing piano',
    'rain sounds',
    'ocean waves',
    'meditation music',
    'deep sleep music',
  ];

  static String? _accessToken;
  static DateTime? _tokenExpiry;

  static bool get _hasValidToken =>
      _accessToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  static Future<String> _getAccessToken() async {
    if (_hasValidToken) {
      return _accessToken!;
    }

    final credentials = base64Encode(
      utf8.encode('${SpotifyConfig.clientId}:${SpotifyConfig.clientSecret}'),
    );

    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'client_credentials',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Spotify authentication failed.');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = payload['access_token'] as String?;
    final expiresIn = (payload['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

    if (_accessToken == null || _accessToken!.isEmpty) {
      throw Exception('Spotify access token is missing.');
    }

    return _accessToken!;
  }

  static Future<List<SpotifyTrack>> fetchMeditationTracks({
    String? query,
  }) async {
    final trimmedQuery = query?.trim() ?? '';
    final token = await _getAccessToken();
    final seenIds = <String>{};
    final tracks = <SpotifyTrack>[];
    final searchTerms = trimmedQuery.isEmpty
        ? suggestedSearchTerms
        : <String>[trimmedQuery];

    for (final term in searchTerms) {
      final uri = Uri.https('api.spotify.com', '/v1/search', {
        'q': term,
        'type': 'track',
        'limit': '10',
        'market': 'US',
      });

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        final payload =
            jsonDecode(response.body) as Map<String, dynamic>? ?? const {};
        final error =
            payload['error'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        final message = error['message'] as String? ?? 'Spotify search failed.';
        throw Exception(message);
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items =
          ((payload['tracks'] as Map<String, dynamic>?)?['items'] as List<dynamic>? ??
              const []);

      for (final item in items) {
        final track = SpotifyTrack.fromJson(item as Map<String, dynamic>);
        if (track.id.isEmpty ||
            track.spotifyUrl.isEmpty ||
            !seenIds.add(track.id)) {
          continue;
        }
        tracks.add(track);
      }
    }

    if (trimmedQuery.isNotEmpty) {
      tracks.sort((a, b) => _compareSongSearchResults(a, b, trimmedQuery));
    }
    return tracks;
  }

  static int _compareSongSearchResults(
    SpotifyTrack a,
    SpotifyTrack b,
    String query,
  ) {
    final normalizedQuery = _normalizeSongText(query);
    final aTitle = _normalizeSongText(a.title);
    final bTitle = _normalizeSongText(b.title);

    final aExact = aTitle == normalizedQuery;
    final bExact = bTitle == normalizedQuery;
    if (aExact != bExact) {
      return aExact ? -1 : 1;
    }

    final aStarts = aTitle.startsWith(normalizedQuery);
    final bStarts = bTitle.startsWith(normalizedQuery);
    if (aStarts != bStarts) {
      return aStarts ? -1 : 1;
    }

    final aContains = aTitle.contains(normalizedQuery);
    final bContains = bTitle.contains(normalizedQuery);
    if (aContains != bContains) {
      return aContains ? -1 : 1;
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  static String _normalizeSongText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<void> openSongOnSpotify(
    BuildContext context,
    String songTitle,
  ) async {
    final uri = Uri.https('open.spotify.com', '/search/$songTitle');
    await _launchSpotifyUri(context, uri);
  }

  static Future<void> openSpotifyTrack(
    BuildContext context,
    String spotifyUrl,
  ) async {
    final uri = Uri.tryParse(spotifyUrl);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This Spotify track link is invalid.'),
        ),
      );
      return;
    }

    await _launchSpotifyUri(context, uri);
  }

  static Future<void> _launchSpotifyUri(
    BuildContext context,
    Uri uri,
  ) async {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Spotify on this device.'),
        ),
      );
    }
  }
}
