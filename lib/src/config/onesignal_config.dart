class OneSignalConfig {
  // The public OneSignal App ID is bundled by default. A dart-define can still
  // override it when building for a different OneSignal environment.
  static const String appId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '784f6967-f624-4b03-ad3c-01a069be927f',
  );
}
