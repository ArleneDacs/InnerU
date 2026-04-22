class SpotifyConfig {
  static const String clientId = '9bbf9346edc042baaf03ab6b60f104fa';
  static const String clientSecret = 'a273663d056e4048b849a1ea8a178341';
  static const String redirectUri = 'inneru://spotify-auth-callback';
  static const List<String> scopes = [
    'app-remote-control',
    'user-read-email',
    'user-read-private',
    'user-read-playback-state',
    'user-modify-playback-state',
  ];
}
