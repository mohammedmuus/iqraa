# Iqraa app (Android and iOS)

Flutter app for the Iqraa library. Application ID and bundle ID: `tz.or.iqraa`. It reads the library from the Django backend through `/api/v1/`. Built for Flutter 3.47.

Tabs: Home, Library, Listen, Dhikr and Support. The account button sits at the top of Home.

## First time setup

This folder holds the app code and the Android and iOS settings that differ from a new Flutter project. Flutter fills in the rest (Gradle wrapper, launcher icons, Xcode project) without touching these files:

```
cd "D:\Django Projects\Iqraa\iqraa_app"
flutter create --org tz.or --project-name iqraa --platforms android,ios .
del test\widget_test.dart
flutter pub get
flutter analyze
```

`flutter create` adds a sample test that does not match this app, so delete it as shown.

## Run against your local Django

The app has to be told where Django is. Debug builds use `10.0.2.2`, which only works inside the Android emulator.

On a real phone (same Wi-Fi as the computer):

1. Find the computer's address with `ipconfig` (IPv4 Address, for example `192.168.2.198`).
2. Put that address in `DJANGO_ALLOWED_HOSTS` in the Django `.env`, then start Django on all addresses:
   ```
   python manage.py runserver 0.0.0.0:8000
   ```
   Plain `runserver` only listens on the computer itself, and the phone cannot reach it.
3. Run the app with the address:
   ```
   flutter run --dart-define=IQRAA_API=http://192.168.2.198:8000
   ```
4. If the phone still cannot connect, open `http://192.168.2.198:8000` in the phone's browser. If that fails too, allow Python through Windows Firewall for private networks.

On the Android emulator: add `10.0.2.2` to `DJANGO_ALLOWED_HOSTS`, run `python manage.py runserver 0.0.0.0:8000` and then `flutter run`.

When the app cannot reach the server, debug builds show the address they tried.

## Offline reading

On a book's page, Save for offline keeps the whole book on the phone: every chapter's text and narration. Saved books show under On this phone on Home and open without internet. Chapters you have opened are also kept for offline reading.

## Language

English is the default. Kiswahili and Arabic can be chosen from the language button on Home. Kiswahili shows the app and the translation in Kiswahili. Arabic shows the app right to left and the books in Arabic only.

## Listening

Narration keeps playing with the screen off, with controls on the lock screen. In the reader the paragraph being read sits on a white card and stays on screen; tap any paragraph to jump the narration there. Saved books play from the phone.

## Accounts and giving

- Sign up sends a 6 digit code by email. Password sign in needs no code.
- After the first sign in the app offers fingerprint or face unlock, asked again after 5 minutes in the background.
- Reading progress and bookmarks follow the reader to every device. Dhikr counts are kept on the phone and sent when signed in.
- Account, Close account deletes the account, as both stores require.
- Android: card gifts open CRDB's page in a Custom Tab; mobile money sends the PIN prompt from the app.
- iPhone: card gifts open CRDB's page in Safari; mobile money opens the website's giving page in Safari (App Store guideline 3.2.2).
- After paying, the thank you page returns to the app through `iqraa://donation/REF` and the gift screen follows the payment until it is confirmed.

## Release builds

Release builds need the live address, because they never fall back to a local server. Always build with `--obfuscate --split-debug-info` and keep `build/symbols` private; it is needed to read crash reports.

### Android (.aab for Google Play)

1. Create the upload key once and keep it safe; losing it blocks updates.
   ```
   keytool -genkey -v -keystore %USERPROFILE%\iqraa-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `android\key.properties` (never committed):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=C:\\Users\\<you>\\iqraa-upload.jks
   ```
   A release bundle refuses to build without it.
3. Build:
   ```
   flutter build appbundle --release --obfuscate --split-debug-info=build\symbols ^
     --dart-define=IQRAA_API=https://iqraa.co.tz ^
     --dart-define=IQRAA_CERT_PINS=PIN1,PIN2 ^
     --dart-define=IQRAA_CLOUD_PROJECT=GOOGLE_CLOUD_PROJECT_NUMBER ^
     --dart-define=IQRAA_SIGNING_HASHES=BASE64_SHA256_OF_PLAY_APP_SIGNING_KEY ^
     --dart-define=IQRAA_SECURITY_MAIL=YOUR_SECURITY_EMAIL
   ```
   The bundle is `build\app\outputs\bundle\release\app-release.aab`. Upload `build\symbols` as the debug symbols file.
4. Turn on Play App Signing. Convert its SHA-256 to base64 for `IQRAA_SIGNING_HASHES`:
   `python -c "import base64,sys;print(base64.b64encode(bytes.fromhex(sys.argv[1].replace(':',''))).decode())" HEX`, then rebuild.
5. Check "Memory page size: supports 16 KB" in the Play Console bundle details.

### Android APK for the website (GitHub release)

The website's "Download for Android" button points to an APK in a GitHub release. That copy is installed outside Google Play, so it is built with `IQRAA_DIRECT=true`, which skips only the store check. It is signed with the upload key, so `IQRAA_SIGNING_HASHES` is the base64 SHA-256 of the upload key (from `keytool -list -v -keystore iqraa-upload.jks -alias upload`, converted as in step 4). One APK covers every Android phone from Android 7.0 (32 bit, 64 bit and x86).
```
flutter build apk --release --obfuscate --split-debug-info=build\symbols ^
  --dart-define=IQRAA_DIRECT=true ^
  --dart-define=IQRAA_SIGNING_HASHES=BASE64_SHA256_OF_UPLOAD_KEY ^
  --dart-define=IQRAA_SECURITY_MAIL=info@iqraa.co.tz
```
Rename `build\app\outputs\flutter-apk\app-release.apk` to `iqraa.apk` and attach it to the GitHub release. With the same file name on every release, `https://github.com/OWNER/REPO/releases/latest/download/iqraa.apk` always gives the newest copy, so the link in Site settings, Stores, Android download link never changes. Raise `version` in `pubspec.yaml` before each release and set the same number as the newest Android version in Site settings.

### iPhone (on Codemagic)

`codemagic.yaml` has three workflows: `ios-check` (build without signing), `ios-sideload` (test IPA for AltServer, protection off) and `ios-testflight` (signed, sent to TestFlight). Before the first signed build, in the Apple Developer account enable App Attest for `tz.or.iqraa`, and in Xcode add the App Attest capability to Runner (Signing and Capabilities) so `ios/Runner/Runner.entitlements` is used. The app supports iPhone and iPad, so App Store Connect needs iPhone 6.9 inch and iPad 13 inch screenshots.

## Hardening

- freeRASP (Talsec) runs in release builds. A rooted or jailbroken phone, Frida or other hooking tools, a debugger, an emulator, a changed or re-signed copy, an install from outside the stores, moved app data or automation signs the reader out and shows the blocked screen. Talsec sends a weekly security report to `IQRAA_SECURITY_MAIL`.
- Sign in, sign up, code, reset and close account screens are hidden from screenshots and screen recording. Android ignores taps while another app draws over Iqraa.
- Play Integrity (Android) and App Attest (iPhone) proofs go with every sign in, sign up and gift. On the server set `APP_INTEGRITY=off` while developing, `report` after launch (logs failures) and `enforce` once the logs are clean. Play Integrity needs `PLAY_INTEGRITY_CREDENTIALS` (a service account JSON with the Play Integrity role, linked in Play Console under App integrity); App Attest needs `APPLE_TEAM_ID` and `APP_ATTEST_PRODUCTION=True` for App Store builds.
- Certificate pinning: run `python manage.py app_pins` on the server once the live domain has its certificate, and pass the pin plus a backup pin in `IQRAA_CERT_PINS`. Leave it empty on hosts whose certificate you do not control.
- App data is excluded from cloud backup and phone transfer, plain http only works in debug builds, the refresh token lives in the phone's secure storage and only public library content is cached.
- A test build for sideloading turns protection off with `--dart-define=IQRAA_SHIELD=false --dart-define=IQRAA_INTEGRITY=false`. Store builds never do.

## Store review notes

- Give reviewers a demo account in the review notes, and keep CRDB in test mode and CashPay in practice mode during review.
- Review notes: "Iqraa is a free library of classical Islamic books with Kiswahili and English translations and narration. Donations go to [REGISTERED NONPROFIT NAME], a registered nonprofit in Tanzania. Card payments open CRDB Bank's secure page in the browser; the app never sees card details. Accounts can be closed under Account, Close account."
- Google Play: send the nonprofit registration and tax exemption letter in the Payments policy declaration, because donations do not use Play billing.
- Data safety and privacy labels: email, name, purchase history (gifts), app activity (reading progress, bookmarks, dhikr counts) and device identifiers for security checks. Not sold, not used for tracking, encrypted in transit, deletable in the app and at `/close-account/`. Privacy policy: `/privacy/`.
