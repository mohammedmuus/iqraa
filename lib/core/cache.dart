import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'json_work.dart';

/// Public library content only, so books stay readable offline. Personal data is never written here.
/// Each response is kept as its own file and read or written off the main thread, so opening a large book
/// never stalls the screen.
class PublicCache {
  PublicCache(this.api);

  final Api api;
  Directory? _folder;

  Future<Directory> _dir() async {
    final existing = _folder;
    if (existing != null) {
      return existing;
    }
    final folder = Directory('${(await getApplicationSupportDirectory()).path}/public_cache');
    await folder.create(recursive: true);
    _folder = folder;
    unawaited(_forgetOldCopies());
    return folder;
  }

  /// Earlier versions kept these copies in the phone's settings store, which slowed every app start.
  Future<void> _forgetOldCopies() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((key) => key.startsWith('public:')).toList()) {
      await prefs.remove(key);
    }
  }

  Future<File> _file(String path, Map<String, String>? query) async {
    final key = '$path?${query == null ? '' : Uri(queryParameters: query).query}';
    return File('${(await _dir()).path}/${sha1.convert(utf8.encode(key))}.json');
  }

  /// Loads from the server and keeps a copy. With [onUpdate], a saved copy is returned straight away and the
  /// server is asked in the background; [onUpdate] then receives the new data when it has changed.
  Future<Map<String, dynamic>> load(String path, {Map<String, String>? query, void Function(Map<String, dynamic>)? onUpdate}) async {
    final file = await _file(path, query);
    if (onUpdate != null) {
      final saved = await _read(file);
      if (saved != null) {
        unawaited(_fetch(path, query, file).then((fresh) {
          if (fresh != null && fresh.$2 != saved.$2) {
            onUpdate(fresh.$1);
          }
        }, onError: (Object _) {}));
        return saved.$1;
      }
    }
    try {
      return (await _fetch(path, query, file))!.$1;
    } on ApiException catch (error) {
      final saved = error.isOffline ? await _read(file) : null;
      if (saved != null) {
        return saved.$1;
      }
      rethrow;
    }
  }

  /// The decoded data and its text, so a background refresh can tell whether anything changed.
  Future<(Map<String, dynamic>, String)?> _fetch(String path, Map<String, String>? query, File file) async {
    final data = await api.get(path, query: query);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{'results': data};
    final text = await encodeJson(map);
    await file.writeAsString(text, flush: true);
    return (map, text);
  }

  Future<(Map<String, dynamic>, String)?> _read(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final text = await file.readAsString();
      final map = await decodeMap(text);
      return (map, text);
    } on Object {
      return null;
    }
  }
}
