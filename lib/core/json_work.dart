import 'dart:convert';

import 'package:flutter/foundation.dart';

/// JSON work for large replies and saved chapters, done on a background isolate so the screen keeps moving.
/// Only the text or data crosses to the other isolate, never the object that asked for it.
Future<Object?> decodeJson(String text) async => text.length < 20000 ? jsonDecode(text) : compute(_decode, text);

Future<Map<String, dynamic>> decodeMap(String text) async => Map<String, dynamic>.from((await decodeJson(text)) as Map);

Future<String> encodeJson(Object? value) => compute(_encode, value);

Object? _decode(String text) => jsonDecode(text);

String _encode(Object? value) => jsonEncode(value);
