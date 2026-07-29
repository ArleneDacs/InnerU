class OneSignalConfig {
  // Pass this at build time with:
  // flutter build <target> --dart-define=ONESIGNAL_APP_ID=your-app-id
  static const String appId = String.fromEnvironment('ONESIGNAL_APP_ID');
}
