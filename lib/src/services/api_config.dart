class ApiConfig {
  static const String _overrideBaseUrl =
      String.fromEnvironment('INNERU_API_BASE_URL');

  static String get baseUrl {
    if (_overrideBaseUrl.isNotEmpty) {
      return _overrideBaseUrl;
    }

    return 'https://inneru-api.valenin.com';
  }
}
