import 'dart:convert';

import 'package:flutter/services.dart';

import 'api.dart';
import 'cache.dart';
import 'strings.dart';

/// Feeds the home screen light bulb. The widget dims the longer the reader stays away and shows a firmer verse,
/// so it needs to know when the app was last opened and the verses in the reader's language.
class Lamp {
  Lamp._();

  static const _channel = MethodChannel('tz.or.iqraa/widget');

  /// Runs when the app opens or comes back to the front, and when the language changes.
  static Future<void> refresh(PublicCache cache, String language) async {
    String t(String key) => Strings.of(language, key);
    var stages = <List<Map<String, String>>>[];
    try {
      final data = await cache.load('lamp');
      stages = [
        for (final stage in (data['stages'] as List? ?? const []))
          [
            for (final row in (stage as List))
              {
                'text': _text(Map<String, dynamic>.from(row as Map), language),
                'ref': '${row['surah']} ${row['ref']}',
              },
          ],
      ];
    } on ApiException {
      // The light still dims and shows its words without verses until the phone is back online.
    }
    final payload = {
      'opened': DateTime.now().millisecondsSinceEpoch,
      'rtl': language == 'ar',
      'labels': {'today': t('lamp_today'), 'one': t('lamp_one'), 'days': t('lamp_days'), 'out': t('lamp_out'), 'empty': t('lamp_empty')},
      'stages': stages,
    };
    try {
      await _channel.invokeMethod<void>('update', jsonEncode(payload));
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// The approved translation in the reader's language, or the Arabic when there is none yet.
  static String _text(Map<String, dynamic> row, String language) {
    final translated = (row[language] ?? '').toString().trim();
    return language == 'ar' || translated.isEmpty ? (row['ar'] ?? '').toString() : translated;
  }
}
