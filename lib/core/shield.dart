import 'package:flutter/foundation.dart';
import 'package:freerasp/freerasp.dart';

import '../config.dart';
import 'session.dart';

/// Runtime protection in release builds: rooted or jailbroken phones, hooking tools, debuggers, emulators,
/// changed or re-signed copies, installs from outside the official stores, moved app data and automation.
/// Any of these signs the reader out and shows the blocked screen. [blocked] holds the text key of the reason.
class Shield {
  Shield._();

  static final ValueNotifier<String?> blocked = ValueNotifier<String?>(null);

  static Future<void> start(Session session) async {
    if (!AppConfig.shield) {
      return;
    }
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: AppConfig.packageName,
        signingCertHashes: AppConfig.signingHashes.split(',').where((hash) => hash.isNotEmpty).toList(),
      ),
      iosConfig: IOSConfig(bundleIds: const [AppConfig.packageName], teamId: AppConfig.teamId),
      watcherMail: AppConfig.securityMail,
      isProd: true,
      killOnBypass: true,
    );

    Future<void> stop(String reason) async {
      if (blocked.value == null) {
        blocked.value = reason;
        await session.clear();
      }
    }

    await Talsec.instance.attachListener(
      ThreatCallback(
        onPrivilegedAccess: () => stop('threat_root'),
        onHooks: () => stop('threat_hooks'),
        onAppIntegrity: () => stop('threat_tamper'),
        onDebug: () => stop('threat_debug'),
        onSimulator: () => stop('threat_emulator'),
        onUnofficialStore: () {
          if (!AppConfig.directDownload) {
            stop('threat_store');
          }
        },
        onDeviceBinding: () => stop('threat_binding'),
        onAutomation: () => stop('threat_automation'),
      ),
    );
    await Talsec.instance.start(config);
  }

  static int _protected = 0;

  /// Hides screens from screenshots, screen recording and the recent apps preview. Each protected screen calls
  /// this with true when it opens and false when it closes; capture stays blocked while any of them is open.
  static Future<void> protectScreen(bool enabled) async {
    _protected = (_protected + (enabled ? 1 : -1)).clamp(0, 50);
    if (!AppConfig.shield) {
      return;
    }
    try {
      await Talsec.instance.blockScreenCapture(enabled: _protected > 0);
    } on Object {
      return;
    }
  }
}
