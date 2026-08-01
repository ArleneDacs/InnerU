# selfcare_projects

A new Flutter project.

This workspace now also includes a Laravel backend in [`/backend`](/Users/arlenedacanay/InnerU/backend) for the Firebase-to-PostgreSQL migration.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android release signing

Play Console rejects APKs and AABs signed with the debug key. This project expects
an Android release keystore configured through `android/key.properties`.

1. Generate an upload keystore:

```powershell
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Create `android/key.properties` from [`android/key.properties.example`](android/key.properties.example) and set the real values:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=upload
storeFile=../upload-keystore.jks
```

3. Copy the OneSignal App ID from OneSignal **Settings > Keys & IDs**, then
   provide it to every Flutter run/build. The App ID is safe to include in the
   client; never include the OneSignal REST API key in Flutter.

```powershell
flutter run --dart-define=ONESIGNAL_APP_ID="your-onesignal-app-id"
```

4. Build a release artifact with the same App ID:

```powershell
flutter build appbundle --release --dart-define=ONESIGNAL_APP_ID="your-onesignal-app-id"
flutter build ipa --release --dart-define=ONESIGNAL_APP_ID="your-onesignal-app-id"
```

If `android/key.properties` is missing, release builds now fail immediately instead
of producing an artifact that may be signed incorrectly.

## GitHub Actions release secrets

If you want GitHub Actions to build the Android release for you, add these
repository secrets:

- `ONESIGNAL_APP_ID`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

`ANDROID_KEYSTORE_BASE64` should be the base64-encoded contents of
`upload-keystore.jks`. The release workflow writes `android/key.properties`
automatically and passes `ONESIGNAL_APP_ID` into the Flutter build.

## Backend OneSignal env

The Laravel backend sends the push notification and still needs these
production environment variables:

- `ONESIGNAL_APP_ID`
- `ONESIGNAL_REST_API_KEY`

If those are already set on the server, no extra server change is needed.
If not, add them to the backend `.env` before deploying so push delivery works
for production notifications.

The Flutter App ID and backend App ID must be identical. After changing backend
environment values, clear Laravel's cached configuration before testing.

## iOS push capability

The Runner target includes the APNs entitlement and the Remote notifications
background mode. In Apple Developer, enable **Push Notifications** for
`com.valenin.inneru`, regenerate both development and App Store provisioning
profiles, and configure the matching APNs key in OneSignal. A provisioning
profile created before Push Notifications was enabled cannot register the
device with APNs.
