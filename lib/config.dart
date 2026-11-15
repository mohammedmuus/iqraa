import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  /// Debug builds talk to Django on the computer running the Android emulator. Release builds talk to the
  /// live site unless --dart-define=IQRAA_API gives another address.
  static const apiBase = String.fromEnvironment('IQRAA_API', defaultValue: kReleaseMode ? 'https://iqraa.co.tz' : 'http://10.0.2.2:8000');
  static const certPins = String.fromEnvironment('IQRAA_CERT_PINS');
  static const cloudProject = String.fromEnvironment('IQRAA_CLOUD_PROJECT');
  static const integrity = bool.fromEnvironment('IQRAA_INTEGRITY', defaultValue: kReleaseMode);
  static const shield = bool.fromEnvironment('IQRAA_SHIELD', defaultValue: kReleaseMode);

  /// The APK offered on the website and GitHub is installed outside the stores, so that build skips only the
  /// store check. Every other protection stays on.
  static const directDownload = bool.fromEnvironment('IQRAA_DIRECT');
  static const signingHashes = String.fromEnvironment('IQRAA_SIGNING_HASHES');
  static const teamId = String.fromEnvironment('IQRAA_APPLE_TEAM');
  static const securityMail = String.fromEnvironment('IQRAA_SECURITY_MAIL');
  static const packageName = 'tz.or.iqraa';
  static const lockAfter = Duration(minutes: 5);

  static List<String> get pins => certPins.split(',').map((pin) => pin.trim()).where((pin) => pin.isNotEmpty).toList();
}
