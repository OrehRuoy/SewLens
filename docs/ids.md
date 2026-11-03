# SewLens IDs

Store title: SewLens: Sewing Pattern Maker

## Apple

- Bundle ID: `com.sewlens.app`
- SKU: `sewlens-ios`
- Team ID: `9WRNQYQZTB`
- Minimum iOS: 15.0
- Export preset: `iOS (TestFlight IPA)` (`application/export_project_only=true`)
- Release provisioning profile UUID is a placeholder in `export_presets.cfg`. The iOS workflow reads the UUID from `APPLE_PROVISIONING_PROFILE_BASE64` and writes it into the preset before export.
- GitHub secrets (same names as Oil Due): `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_ID_USERNAME`, `APPLE_ID_PASSWORD` (app-specific password used by `altool`).

## Google Play

- Package name: `com.sewlens.app`
- Play Console app: `sewlens-android`
- Export preset: `Android (Play Store .aab)`
- Min SDK: 24
- Target SDK: 36 (Play requires API 36 for new apps as of August 31, 2026)
- GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON`
- Godot signs with one release password (`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` = `ANDROID_KEYSTORE_PASSWORD`). The key password has to match the keystore password.

## IAPs

Created in App Store Connect and Play Console in a later step. Do not submit them yet.

- Per-pattern credit (consumable): `orehruoy.sewlens.credit`
- Unlimited unlock (non-consumable): `orehruoy.sewlens.unlimited`

## Firebase

- Project id: `sewlens-app` (`.firebaserc`)
- Cloud Functions runtime: Node 24 (`functions/`)
- iOS: `ios/GoogleService-Info.plist` (gitignored). The export plugin copies it into the app bundle. CI restores it from `GOOGLE_SERVICE_INFO_PLIST_BASE64`.
- Android: `android/google-services.json` (gitignored). `tools/enable_android_firebase.py` copies it to `android/build/google-services.json` and applies the Google Services plugin. CI restores it from `GOOGLE_SERVICES_JSON_BASE64`.
- Bundle and package on both configs: `com.sewlens.app`

## Store languages

en-US, de-DE, fr-FR, es-ES, pt-BR, ja, it, nl-NL
