import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'cache.dart';
import 'dhikr_store.dart';
import 'downloads.dart';
import 'lamp.dart';
import 'narration.dart';
import 'prefs.dart';
import 'reading_log.dart';
import 'reminders.dart';
import 'rivals.dart';
import 'session.dart';

class AppServices {
  AppServices() : session = Session(), prefs = ReadingPrefs() {
    api = Api(session);
    cache = PublicCache(api);
    downloads = Downloads(api);
    dhikr = DhikrStore(api, cache, session);
    rivals = Rivals(api, session);
    reminders.log = readingLog;
    narration.askToNotify = reminders.askPermission;
    changes = Listenable.merge([session, prefs, downloads, narration, dhikr, reminders, rivals, giving, readingLog]);
    prefs.addListener(_languageChanged);
    session.addListener(_sessionChanged);
  }

  bool _signedIn = false;

  /// Signing out, or the server ending the session, stops the background group check on this phone.
  void _sessionChanged() {
    if (_signedIn && !session.signedIn) {
      unawaited(rivals.stop());
    }
    _signedIn = session.signedIn;
  }

  String? _language;

  /// Reminders are written in the app language, so they are scheduled again when it changes.
  void _languageChanged() {
    if (_language != null && _language != prefs.language) {
      reminders.schedule(prefs.language);
      unawaited(Lamp.refresh(cache, prefs.language));
    }
    _language = prefs.language;
  }

  final Session session;
  final ReadingPrefs prefs;
  final Narration narration = Narration();
  final Reminders reminders = Reminders();
  final ReadingLog readingLog = ReadingLog();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final Api api;
  late final PublicCache cache;
  late final Downloads downloads;
  late final DhikrStore dhikr;
  late final Rivals rivals;
  late final Listenable changes;
  Map<String, dynamic> config = const {};

  /// Staff turn giving on in Site settings. Until then the Support tab is hidden.
  final ValueNotifier<bool> giving = ValueNotifier(false);

  /// A group invite opened before signing in; the group is joined straight after sign in.
  String? pendingInvite;

  /// A book's details: from the server, else the copy saved on the phone when there is no connection.
  Future<Map<String, dynamic>> book(String bookId, {void Function(Map<String, dynamic>)? onUpdate}) async {
    try {
      return await cache.load('books/$bookId', onUpdate: onUpdate);
    } on ApiException catch (error) {
      final saved = error.isOffline ? await downloads.book(bookId) : null;
      if (saved != null) {
        return saved;
      }
      rethrow;
    }
  }

  /// A chapter's text and narration. Saved audio files are attached so playback works offline.
  /// With [onUpdate], a copy kept on the phone opens at once and newer text arrives through it.
  Future<Map<String, dynamic>> chapter(String chapterId, {void Function(Map<String, dynamic>)? onUpdate}) async {
    final saved = await downloads.chapter(chapterId);
    void attach(Map<String, dynamic> data) {
      if (saved == null) {
        return;
      }
      // Matched by language and reader, since the Quran can have several reciters and only one is saved.
      String key(Map audio) => '${audio['language']}|${audio['narrator'] ?? ''}';
      final files = {for (final entry in (saved['audio'] as List? ?? const [])) key(entry as Map): entry['file']};
      for (final entry in (data['audio'] as List? ?? const [])) {
        final audio = entry as Map;
        if (files[key(audio)] != null) {
          audio['file'] = files[key(audio)];
        }
      }
    }

    Map<String, dynamic> data;
    try {
      data = await cache.load(
        'chapters/$chapterId',
        onUpdate: onUpdate == null
            ? null
            : (fresh) {
                attach(fresh);
                onUpdate(fresh);
              },
      );
    } on ApiException catch (error) {
      if (error.isOffline && saved != null) {
        return saved;
      }
      rethrow;
    }
    attach(data);
    return data;
  }
}

class AppScope extends InheritedNotifier<Listenable> {
  AppScope({super.key, required this.services, required super.child}) : super(notifier: services.changes);

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.services;
  }

  static AppServices read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AppScope>()!.services;
  }
}
