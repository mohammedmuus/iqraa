import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:url_launcher/url_launcher.dart' as browser;

import '../config.dart';
import '../theme.dart';

class Payments {
  Payments._();

  /// The website's giving page, for readers who give without an account or with mobile money on iPhone.
  static Uri get websiteGiving => Uri.parse('${AppConfig.apiBase}/donate/');

  /// iPhone: the page opens in Safari, outside the app, as App Store rule 3.2.2 asks of donation apps that do not
  /// take Apple Pay. Android: a Custom Tab, which is the phone's own browser, never a WebView. Card details never
  /// pass through the app.
  static Future<void> openSecurePage(Uri url) async {
    if (Platform.isIOS) {
      await browser.launchUrl(url, mode: browser.LaunchMode.externalApplication);
      return;
    }
    await launchUrl(
      url,
      customTabsOptions: CustomTabsOptions(
        colorSchemes: CustomTabsColorSchemes.defaults(toolbarColor: Palette.ink),
        shareState: CustomTabsShareState.off,
        showTitle: true,
      ),
      safariVCOptions: SafariViewControllerOptions(
        preferredBarTintColor: Palette.ink,
        preferredControlTintColor: Colors.white,
        dismissButtonStyle: SafariViewControllerDismissButtonStyle.close,
      ),
    );
  }

  static Future<void> closeSecurePage() async {
    try {
      await closeCustomTabs();
    } on Object {
      return;
    }
  }

  /// Gift reference from the link the thank you page opens: iqraa://donation/REF.
  static String? referenceFrom(Uri uri) {
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri.scheme == 'iqraa' && uri.host == 'donation' && segments.length == 1 && RegExp(r'^IQ[A-Z0-9]{10}$').hasMatch(segments.first)) {
      return segments.first;
    }
    return null;
  }

  /// Invite code from a group link: iqraa://join/CODE.
  static String? inviteFrom(Uri uri) {
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri.scheme == 'iqraa' && uri.host == 'join' && segments.length == 1) {
      final code = segments.first.toUpperCase();
      return RegExp(r'^[A-Z0-9]{8}$').hasMatch(code) ? code : null;
    }
    return null;
  }

  /// Tanzanian mobile numbers in any common form, returned as 255XXXXXXXXX, or null.
  static String? phone(String value) {
    final digits = value.replaceAll(RegExp(r'[\s()+-]'), '');
    final match = RegExp(r'^(?:255|0)?([67]\d{8})$').firstMatch(digits);
    return match == null ? null : '255${match.group(1)}';
  }
}
