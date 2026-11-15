import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../config.dart';
import 'api.dart';

/// Proves to the server that a sign in or gift comes from the genuine app: Play Integrity on Android,
/// App Attest on iPhone. The server issues a single use nonce for each check.
class Integrity {
  Integrity._();

  static const _channel = MethodChannel('tz.or.iqraa/integrity');

  static Future<Map<String, String>> headers(Api api) async {
    if (!AppConfig.integrity) {
      return const {};
    }
    try {
      final data = await api.get('integrity/nonce') as Map;
      final nonce = data['nonce'] as String;
      final result = await _channel.invokeMethod<Object>('token', {'nonce': nonce, 'project': AppConfig.cloudProject}).timeout(const Duration(seconds: 12));
      if (result is String && Platform.isAndroid) {
        return {'X-Integrity': 'android $result', 'X-Integrity-Nonce': nonce};
      }
      if (result is Map) {
        return {'X-Integrity': 'ios-${result['kind']} ${result['key_id']}.${result['data']}', 'X-Integrity-Nonce': nonce};
      }
    } on Object {
      return const {};
    }
    return const {};
  }
}
