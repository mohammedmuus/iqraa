import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'json_work.dart';
import 'narration.dart';

/// Books saved on the phone with their chapters and narration, so they read and play without internet.
/// Everything lives in the app's private support folder. Only public library content is stored.
class Downloads extends ChangeNotifier {
  Downloads(this.api);

  final Api api;
  Directory? _root;
  Map<String, dynamic> _books = {};
  Map<String, dynamic> _chapters = {};

  /// Book id to share saved so far, from 0 to 1, while a save is running.
  final Map<String, double> progress = {};

  /// Saves the reader asked to stop. Each one ends at the next chapter or audio file.
  final Set<String> _stopping = {};

  /// Stops a save and removes what it had saved so far.
  void stop(String bookId) {
    if (progress.containsKey(bookId)) {
      _stopping.add(bookId);
    }
  }

  Future<void> load() async {
    try {
      _root = Directory('${(await getApplicationSupportDirectory()).path}/library');
      final index = File('${_root!.path}/index.json');
      if (await index.exists()) {
        final data = jsonDecode(await index.readAsString()) as Map;
        _books = Map<String, dynamic>.from(data['books'] as Map? ?? const {});
        _chapters = Map<String, dynamic>.from(data['chapters'] as Map? ?? const {});
      }
    } on Object {
      _books = {};
      _chapters = {};
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get books {
    final rows = [for (final row in _books.values) Map<String, dynamic>.from(row as Map)];
    rows.sort((a, b) => (b['saved_at'] ?? '').toString().compareTo((a['saved_at'] ?? '').toString()));
    return rows;
  }

  bool has(String bookId) => _books.containsKey(bookId);

  Future<Map<String, dynamic>?> book(String bookId) => _readJson(has(bookId) ? 'books/$bookId/book.json' : null);

  Future<Map<String, dynamic>?> chapter(String chapterId) async {
    final bookId = _chapters[chapterId];
    final data = await _readJson(bookId == null ? null : 'books/$bookId/chapters/$chapterId.json');
    if (data == null) {
      return null;
    }
    // Audio is stored by a path inside the library folder, because the app folder can move on updates.
    for (final entry in (data['audio'] as List? ?? const [])) {
      final audio = entry as Map;
      if (audio['file'] != null) {
        audio['file'] = '${_root!.path}/books/$bookId/${audio['file']}';
      }
    }
    return data;
  }

  /// Saves a book with its chapters and narration. It runs on its own, so the reader can leave the book's page
  /// while it saves. Chapters come in batches, and a save that fails part way carries on from there next time.
  /// Returns false when the reader stopped it.
  Future<bool> save(String bookId) async {
    final root = _root;
    if (root == null || progress.containsKey(bookId)) {
      return false;
    }
    progress[bookId] = 0;
    notifyListeners();
    final work = Directory('${root.path}/books/$bookId.part');
    var finished = false;
    var stopped = false;
    void checkStop() {
      if (_stopping.contains(bookId)) {
        throw const _Stopped();
      }
    }

    try {
      await Directory('${work.path}/chapters').create(recursive: true);
      final book = Map<String, dynamic>.from(await _retry(() => api.get('books/$bookId')) as Map);
      // Only the chosen Quran reciter is saved, so a book does not take several times the space.
      final reciter = (await SharedPreferences.getInstance()).getString('reciter');
      final chapters = [for (final row in (book['chapters'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
      final total = chapters.isEmpty ? 1 : chapters.length;
      var done = 0;
      int? next = 0;
      while (next != null) {
        final start = next;
        final batch = Map<String, dynamic>.from(await _retry(() => api.get('books/$bookId/chapters', query: {'start': '$start'})) as Map);
        for (final row in (batch['results'] as List? ?? const [])) {
          checkStop();
          final data = Map<String, dynamic>.from(row as Map);
          final chapterId = data['id'].toString();
          final saved = File('${work.path}/chapters/$chapterId.json');
          if (!await saved.exists()) {
            final recitation = Narration.pickTrack(data, 'ar', reciter: reciter);
            for (final entry in (data['audio'] as List? ?? const [])) {
              final audio = entry as Map;
              final url = (audio['url'] ?? '').toString();
              if (url.isEmpty || (audio['language'] == 'ar' && recitation != null && audio['narrator'] != recitation['narrator'])) {
                continue;
              }
              final name = 'audio/$chapterId-${audio['language']}${_extension(url)}';
              final file = File('${work.path}/$name');
              if (!await file.exists()) {
                checkStop();
                await _retry(() => api.download(url, file));
              }
              audio['file'] = name;
            }
            final text = await encodeJson(data);
            await saved.writeAsString(text);
          }
          done++;
          progress[bookId] = done / total;
          notifyListeners();
        }
        next = (batch['next_start'] as num?)?.toInt();
        checkStop();
      }
      await File('${work.path}/book.json').writeAsString(jsonEncode(book));
      final folder = Directory('${root.path}/books/$bookId');
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
      await work.rename(folder.path);
      finished = true;
      _chapters.removeWhere((_, owner) => owner == bookId);
      for (final chapter in chapters) {
        _chapters[chapter['id'].toString()] = bookId;
      }
      _books[bookId] = {
        for (final key in ['id', 'title', 'arabic_title', 'author', 'author_arabic', 'subject', 'cover_colour']) key: book[key],
        'saved_at': DateTime.now().toIso8601String(),
      };
      await _writeIndex();
    } on _Stopped {
      stopped = true;
    } finally {
      // After a failure what was saved stays in the work folder, so the next try continues from there.
      // A save the reader stopped leaves nothing behind.
      if ((finished || stopped) && await work.exists()) {
        await work.delete(recursive: true);
      }
      _stopping.remove(bookId);
      progress.remove(bookId);
      notifyListeners();
    }
    return !stopped;
  }

  /// Tries again after a pause when the connection drops or the server asks the app to slow down.
  Future<T> _retry<T>(Future<T> Function() call) async {
    const waits = [2, 5, 15, 30, 60];
    for (var attempt = 0;; attempt++) {
      try {
        return await call();
      } on ApiException catch (error) {
        final passing = error.isOffline || error.status == 429 || error.status >= 500;
        if (!passing || attempt >= waits.length) {
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: waits[attempt]));
      }
    }
  }

  /// Space a saved book takes on the phone, in bytes.
  Future<int> sizeOf(String bookId) async {
    final root = _root;
    final folder = root == null ? null : Directory('${root.path}/books/$bookId');
    if (folder == null || !await folder.exists()) {
      return 0;
    }
    var total = 0;
    await for (final entry in folder.list(recursive: true, followLinks: false)) {
      if (entry is File) {
        total += await entry.length();
      }
    }
    return total;
  }

  Future<void> remove(String bookId) async {
    final root = _root;
    if (root == null) {
      return;
    }
    for (final folder in [Directory('${root.path}/books/$bookId'), Directory('${root.path}/books/$bookId.part')]) {
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    }
    _books.remove(bookId);
    _chapters.removeWhere((_, owner) => owner == bookId);
    await _writeIndex();
    notifyListeners();
  }

  String _extension(String url) {
    final path = Uri.parse(url).path;
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot).toLowerCase();
    return const ['.mp3', '.m4a', '.aac', '.ogg', '.opus', '.wav'].contains(ext) ? ext : '.mp3';
  }

  Future<Map<String, dynamic>?> _readJson(String? relative) async {
    if (relative == null || _root == null) {
      return null;
    }
    try {
      final file = File('${_root!.path}/$relative');
      if (!await file.exists()) {
        return null;
      }
      final text = await file.readAsString();
      return await decodeMap(text);
    } on Object {
      return null;
    }
  }

  Future<void> _writeIndex() async {
    final index = File('${_root!.path}/index.json');
    await index.parent.create(recursive: true);
    final temp = File('${index.path}.tmp');
    await temp.writeAsString(jsonEncode({'books': _books, 'chapters': _chapters}));
    await temp.rename(index.path);
  }
}

class _Stopped implements Exception {
  const _Stopped();
}
