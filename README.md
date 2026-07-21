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

3. Build a release artifact:

```powershell
flutter build appbundle --release
```

If `android/key.properties` is missing, release builds now fail immediately instead
of producing an artifact that may be signed incorrectly.
