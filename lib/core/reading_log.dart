import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the reader has read, kept on the phone: for each book the chapters finished, the ayat read in the
/// Quran and where they stopped, plus the days they read for the streak. It works without an account.
class ReadingLog extends ChangeNotifier {
  static const _booksKey = 'reading_log';
  static const _daysKey = 'reading_days';
  static const _maxDays = 400;

  /// Book id to {title, quran, total, done: [chapter ids], ayat, chapter, chapter_title, paragraph, at}.
  Map<String, Map<String, dynamic>> _books = {};
  Set<String> _days = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString(_booksKey) ?? '{}') as Map;
      _books = {for (final entry in saved.entries) entry.key.toString(): Map<String, dynamic>.from(entry.value as Map)};
    } on FormatException {
      _books = {};
    }
    _days = (prefs.getStringList(_daysKey) ?? const []).toSet();
    notifyListeners();
  }

  /// The book read most recently, if any.
  Map<String, dynamic>? get last {
    final books = inProgress(limit: 1);
    return books.isEmpty ? null : books.first;
  }

  /// When the reader last opened a chapter.
  DateTime? get lastAt {
    final at = last?['at'];
    return at == null ? null : DateTime.tryParse(at.toString());
  }

  /// Books started and not yet finished, most recent first, each with its id under 'id'.
  List<Map<String, dynamic>> inProgress({int limit = 3}) {
    final rows = [
      for (final entry in _books.entries)
        if (!_finished(entry.value)) {...entry.value, 'id': entry.key},
    ]..sort((a, b) => (b['at'] ?? '').toString().compareTo((a['at'] ?? '').toString()));
    return rows.take(limit).toList();
  }

  bool _finished(Map<String, dynamic> book) {
    final total = (book['total'] as num?)?.toInt() ?? 0;
    return total > 0 && (book['done'] as List? ?? const []).length >= total;
  }

  /// Days in a row with reading, counting today or, before reading today, up to yesterday.
  int get streak {
    var day = DateTime.now();
    if (!_days.contains(_key(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (_days.contains(_key(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  bool get readToday => _days.contains(_key(DateTime.now()));

  /// Records that a chapter was opened. [total] is the number of chapters in the book when known.
  Future<void> opened({
    required String bookId,
    required String bookTitle,
    required bool quran,
    required String chapterId,
    required String chapterTitle,
    int total = 0,
  }) async {
    final book = _books.putIfAbsent(bookId, () => {'done': <String>[], 'ayat': 0});
    book
      ..['title'] = bookTitle
      ..['quran'] = quran
      ..['chapter'] = chapterId
      ..['chapter_title'] = chapterTitle
      ..['paragraph'] = null
      ..['at'] = DateTime.now().toIso8601String();
    if (total > 0) {
      book['total'] = total;
    }
    _days.add(_key(DateTime.now()));
    await _save();
  }

  /// The paragraph reached in the chapter last opened, so Continue reading opens there.
  Future<void> reached(String bookId, String chapterId, int paragraph) async {
    final book = _books[bookId];
    if (book == null || book['chapter'] != chapterId || book['paragraph'] == paragraph) {
      return;
    }
    book['paragraph'] = paragraph;
    await _save(quiet: true);
  }

  /// Records a chapter read to the end. [paragraphs] is its number of paragraphs, the ayat for the Quran.
  /// Returns false when it was already counted.
  Future<bool> finished(String bookId, String chapterId, int paragraphs) async {
    final book = _books[bookId];
    if (book == null) {
      return false;
    }
    final done = List<String>.from(book['done'] as List? ?? const []);
    if (done.contains(chapterId)) {
      return false;
    }
    done.add(chapterId);
    book['done'] = done;
    book['ayat'] = ((book['ayat'] as num?)?.toInt() ?? 0) + paragraphs;
    await _save();
    return true;
  }

  Future<void> _save({bool quiet = false}) async {
    if (_days.length > _maxDays) {
      final kept = _days.toList()..sort();
      _days = kept.sublist(kept.length - _maxDays).toSet();
    }
    if (!quiet) {
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_booksKey, jsonEncode(_books));
    await prefs.setStringList(_daysKey, _days.toList());
  }

  static String _key(DateTime day) => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
