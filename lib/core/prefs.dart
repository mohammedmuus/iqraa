import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingMode { arabic, both, translation }

/// Page colour in the reader: light, sepia, or night for reading at Fajr and Tahajjud without a bright screen.
enum ReaderTheme { light, sepia, night }

/// The look of the whole app: the phone's own setting, or always light, or always dark.
enum AppLook { phone, light, dark }

/// Choices kept on the phone: app language, what the reader shows and text size.
/// The app language picks the first translation shown. Inside a book the reader can switch to Arabic only,
/// Kiswahili or English without changing the app language.
class ReadingPrefs extends ChangeNotifier {
  static const sizes = [0.9, 1.0, 1.15, 1.3];
  static const languages = ['en', 'sw', 'ar'];

  String language = 'en';
  ReadingMode mode = ReadingMode.both;
  int sizeIndex = 1;
  ReaderTheme theme = ReaderTheme.light;
  AppLook look = AppLook.phone;
  Map<String, dynamic>? lastRead;

  double get textScale => sizes[sizeIndex];
  bool get arabicOnly => language == 'ar';

  /// The translation picked inside a book, separate from the app language: 'sw', 'en', or 'ar' for the
  /// Arabic only. Null follows the app language.
  String? readingLanguage;

  /// The translation shown next to the Arabic, or null when the reader wants the Arabic only.
  String? get translation {
    final picked = readingLanguage ?? (arabicOnly ? 'ar' : language);
    return picked == 'ar' ? null : picked;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = languages.contains(prefs.getString('language')) ? prefs.getString('language')! : 'en';
    mode = ReadingMode.values.firstWhere((value) => value.name == prefs.getString('mode'), orElse: () => ReadingMode.both);
    sizeIndex = (prefs.getInt('size') ?? 1).clamp(0, sizes.length - 1);
    final reading = prefs.getString('reading_language');
    readingLanguage = languages.contains(reading) ? reading : null;
    look = AppLook.values.firstWhere((value) => value.name == prefs.getString('app_look'), orElse: () => AppLook.phone);
    theme = ReaderTheme.values.firstWhere((value) => value.name == prefs.getString('reader_theme'), orElse: () => ReaderTheme.light);
    final saved = prefs.getString('last_read');
    lastRead = saved == null ? null : Map<String, dynamic>.from(jsonDecode(saved) as Map);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    if (!languages.contains(value)) {
      return;
    }
    language = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('language', value);
  }

  /// Picks the translation inside a book in one step, so the page changes once. Choosing a translation while
  /// the page shows Arabic only brings the Arabic and the translation together.
  Future<void> setReadingLanguage(String value) async {
    if (!languages.contains(value)) {
      return;
    }
    readingLanguage = value;
    final showBoth = value != 'ar' && mode == ReadingMode.arabic;
    if (showBoth) {
      mode = ReadingMode.both;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reading_language', value);
    if (showBoth) {
      await prefs.setString('mode', mode.name);
    }
  }

  Future<void> setMode(ReadingMode value) async {
    mode = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('mode', value.name);
  }

  Future<void> nextSize() async {
    sizeIndex = (sizeIndex + 1) % sizes.length;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt('size', sizeIndex);
  }

  Future<void> setLook(AppLook value) async {
    look = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('app_look', value.name);
  }

  /// Whether the app should be dark now, given the look picked and the phone's own setting.
  bool wantsDark(Brightness phone) => switch (look) {
        AppLook.dark => true,
        AppLook.light => false,
        AppLook.phone => phone == Brightness.dark,
      };

  Future<void> nextTheme() async {
    theme = ReaderTheme.values[(theme.index + 1) % ReaderTheme.values.length];
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('reader_theme', theme.name);
  }

  Future<void> remember({required String book, required String bookTitle, required String chapter, required String chapterTitle}) async {
    // Opening the same chapter again keeps the paragraph the reader had reached.
    final place = placeIn(chapter);
    lastRead = {'book': book, 'book_title': bookTitle, 'chapter': chapter, 'chapter_title': chapterTitle, 'paragraph': ?place};
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('last_read', jsonEncode(lastRead));
  }

  /// The paragraph the reader has scrolled to, so Continue reading opens there. Saved quietly, without
  /// redrawing the app, because it changes as the reader scrolls.
  Future<void> rememberPlace(String chapter, int paragraph) async {
    final last = lastRead;
    if (last == null || last['chapter'] != chapter || last['paragraph'] == paragraph) {
      return;
    }
    last['paragraph'] = paragraph;
    await (await SharedPreferences.getInstance()).setString('last_read', jsonEncode(last));
  }

  /// Where to open a chapter: the saved paragraph when it is the chapter last read.
  int? placeIn(String chapter) {
    final last = lastRead;
    return last != null && last['chapter'] == chapter ? (last['paragraph'] as num?)?.toInt() : null;
  }
}
