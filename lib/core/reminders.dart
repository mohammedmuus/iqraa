import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'cities.dart';
import 'prayer_times.dart';
import 'reading_log.dart';
import 'strings.dart';

enum ReminderKind { afterFajr, evening, tahajjud, hourly, friday, fasting }

/// Reminders worked out on the phone from the reader's city: every time is a UTC instant,
/// so each reader is reminded at the right moment where they live, with no server involved.
class Reminders extends ChangeNotifier {
  /// Daytime hours, on the phone's clock, for the hourly dhikr reminder.
  static const firstHour = 8;
  static const lastHour = 21;

  /// iPhones keep at most 64 waiting notifications per app, so the nearest ones are kept and the rest
  /// are added each time the app opens.
  static int get _limit => Platform.isIOS ? 60 : 300;
  static const _days = 10;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool enabled = false;
  bool promptDismissed = false;

  /// The opening takbirs of the adhan at each prayer time. Off until the reader turns it on.
  bool adhan = false;

  /// A nudge every few hours to carry on from where the reader stopped. On unless turned off.
  bool reading = true;
  static const readingEvery = Duration(hours: 3);

  /// No reading nudges between these hours on the phone's clock.
  static const quietFrom = 22;
  static const quietUntil = 6;
  ReadingLog? log;
  DateTime? _plannedAt;

  /// Prayer times the reader typed in, as hour and minute on the phone's clock, by prayer name.
  Map<String, (int, int)> overrides = {};
  static const prayers = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
  String? cityId;
  PrayerMethod? _method;
  AsrMethod asr = AsrMethod.standard;
  Set<ReminderKind> kinds = ReminderKind.values.toSet();

  City? get city => City.byId(cityId);
  PrayerMethod get method => _method ?? city?.method ?? PrayerMethod.mwl;

  PrayerTimes? get times {
    final place = city;
    return place == null ? null : PrayerTimes(latitude: place.latitude, longitude: place.longitude, method: method, asr: asr);
  }

  /// A day's prayer times with any the reader typed in put in place of the worked out ones.
  PrayerDay? dayFor(DateTime date) {
    final calculator = times;
    if (calculator == null) {
      return null;
    }
    final day = calculator.forDate(date);
    DateTime pick(String key, DateTime worked) {
      final typed = overrides[key];
      if (typed == null) {
        return worked;
      }
      final local = worked.toLocal();
      return DateTime(local.year, local.month, local.day, typed.$1, typed.$2).toUtc();
    }

    return PrayerDay(
      fajr: pick('fajr', day.fajr),
      sunrise: pick('sunrise', day.sunrise),
      dhuhr: pick('dhuhr', day.dhuhr),
      asr: pick('asr', day.asr),
      maghrib: pick('maghrib', day.maghrib),
      isha: pick('isha', day.isha),
    );
  }

  /// Today's times where the reader's city is.
  PrayerDay? get today {
    final calculator = times;
    return calculator == null ? null : dayFor(calculator.localDate(DateTime.now()));
  }

  /// Sets the time of one prayer by hand, or with null goes back to the worked out time.
  Future<void> setOverride(String prayer, (int, int)? time, String language) async {
    if (!prayers.contains(prayer)) {
      return;
    }
    if (time == null) {
      overrides.remove(prayer);
    } else {
      overrides[prayer] = time;
    }
    await _changed(language);
  }

  Future<void> setReading(bool on, String language) async {
    reading = on;
    await _changed(language);
  }

  /// After the reader opens a chapter the next nudges move to a few hours from now. Planning runs
  /// at most every 20 minutes, since every waiting reminder is replaced each time.
  Future<void> readingMoved(String language) async {
    final planned = _plannedAt;
    if (!enabled || !reading || (planned != null && DateTime.now().difference(planned) < const Duration(minutes: 20))) {
      return;
    }
    await schedule(language);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('reminders_on') ?? false;
    promptDismissed = prefs.getBool('reminders_prompt_dismissed') ?? false;
    adhan = prefs.getBool('reminders_adhan') ?? false;
    reading = prefs.getBool('reminders_reading') ?? true;
    try {
      final saved = jsonDecode(prefs.getString('reminders_times') ?? '{}') as Map;
      overrides = {
        for (final entry in saved.entries)
          if (prayers.contains(entry.key) && entry.value is List && (entry.value as List).length == 2)
            entry.key.toString(): (((entry.value as List)[0] as num).clamp(0, 23).toInt(), ((entry.value as List)[1] as num).clamp(0, 59).toInt()),
      };
    } on FormatException {
      overrides = {};
    }
    cityId = prefs.getString('reminders_city');
    final method = prefs.getString('reminders_method');
    _method = method == null ? null : PrayerMethod.values.where((value) => value.name == method).firstOrNull;
    asr = prefs.getString('reminders_asr') == AsrMethod.hanafi.name ? AsrMethod.hanafi : AsrMethod.standard;
    final saved = prefs.getStringList('reminders_kinds');
    if (saved != null) {
      kinds = {for (final kind in ReminderKind.values) if (saved.contains(kind.name)) kind};
    }
    notifyListeners();
  }

  Future<void> _init() async {
    if (_ready) {
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
      ),
    );
    _ready = true;
  }

  /// Asks for permission to notify. Returns false when the reader declines.
  Future<bool> askPermission() async {
    await _init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  Future<bool> turnOn(String language) async {
    if (city == null || !await askPermission()) {
      return false;
    }
    enabled = true;
    await _save();
    await schedule(language);
    return true;
  }

  Future<void> turnOff() async {
    enabled = false;
    await _save();
    await _init();
    await _plugin.cancelAllPendingNotifications();
  }

  Future<void> setCity(String id, String language) async {
    cityId = id;
    _method = null;
    await _changed(language);
  }

  Future<void> setMethod(PrayerMethod value, String language) async {
    _method = value;
    await _changed(language);
  }

  Future<void> setAsr(AsrMethod value, String language) async {
    asr = value;
    await _changed(language);
  }

  Future<void> toggle(ReminderKind kind, bool on, String language) async {
    on ? kinds.add(kind) : kinds.remove(kind);
    await _changed(language);
  }

  Future<void> setKinds(Set<ReminderKind> value, String language) async {
    kinds = {...value};
    await _changed(language);
  }

  Future<void> setAdhan(bool on, String language) async {
    adhan = on;
    if (on && Platform.isAndroid) {
      // Exact timing needs the phone's Alarms and reminders permission. Without it the adhan still
      // plays, only a little late.
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.canScheduleExactNotifications() == false) {
        await android?.requestExactAlarmsPermission();
      }
    }
    await _changed(language);
  }

  /// Congratulates the reader once for each chapter they finish, when notifications are allowed.
  Future<void> chapterFinished(String chapterId, String chapterTitle, String language) async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getStringList('chapters_done') ?? <String>[];
    if (done.contains(chapterId)) {
      return;
    }
    final kept = done.length < 2000 ? done : done.sublist(done.length - 1999);
    await prefs.setStringList('chapters_done', [...kept, chapterId]);
    await _init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() == false) {
        return;
      }
    }
    String t(String key, [Map<String, Object> values = const {}]) => Strings.of(language, key, values);
    await _plugin.show(
      id: _chapterId,
      title: t('chapter_note_title'),
      body: chapterTitle.isEmpty ? t('chapter_done_body') : t('chapter_note_body', {'chapter': chapterTitle}),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('tz.or.iqraa.progress', t('channel_progress'), icon: 'ic_notification'),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: false),
      ),
    );
  }

  /// Silences an adhan that is playing, used when the reader opens the app.
  Future<void> stopAdhan() async {
    if (!Platform.isAndroid || !_ready) {
      return;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final shown in await android?.getActiveNotifications() ?? const <ActiveNotification>[]) {
      if (shown.channelId == _adhanChannel && shown.id != null) {
        await _plugin.cancel(id: shown.id!);
      }
    }
  }

  Future<void> dismissPrompt() async {
    promptDismissed = true;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool('reminders_prompt_dismissed', true);
  }

  Future<void> _changed(String language) async {
    await _save();
    if (enabled) {
      await schedule(language);
    }
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminders_on', enabled);
    await prefs.setBool('reminders_adhan', adhan);
    await prefs.setBool('reminders_reading', reading);
    await prefs.setString('reminders_times', jsonEncode({for (final entry in overrides.entries) entry.key: [entry.value.$1, entry.value.$2]}));
    if (cityId != null) {
      await prefs.setString('reminders_city', cityId!);
    }
    _method == null ? await prefs.remove('reminders_method') : await prefs.setString('reminders_method', _method!.name);
    await prefs.setString('reminders_asr', asr.name);
    await prefs.setStringList('reminders_kinds', [for (final kind in kinds) kind.name]);
  }

  /// Replaces every waiting reminder with the next ones. Runs when the app opens, comes back to the front,
  /// or a setting or the app language changes.
  Future<void> schedule(String language) async {
    final calculator = times;
    if (!enabled || calculator == null) {
      return;
    }
    await _init();
    _plannedAt = DateTime.now();
    final now = DateTime.now().toUtc();
    final due = _plan(calculator, now, language)..sort((a, b) => a.at.compareTo(b.at));
    // Only waiting reminders are replaced, so alerts already on the screen stay.
    await _plugin.cancelAllPendingNotifications();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    var id = 0;
    for (final item in due.take(_limit)) {
      await _plugin.zonedSchedule(
        id: id++,
        title: item.title,
        body: item.body,
        scheduledDate: tz.TZDateTime.from(item.at, tz.UTC),
        notificationDetails: item.prayer ? _adhanDetails(language) : (item.reading ? _readingDetails(language) : _details(item.kind, language)),
        androidScheduleMode: item.prayer && exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  List<_Due> _plan(PrayerTimes calculator, DateTime now, String language) {
    String t(String key, [Map<String, Object> values = const {}]) => Strings.of(language, key, values);
    final due = <_Due>[];
    void add(ReminderKind kind, DateTime at, String title, String body, {bool prayer = false, bool reading = false}) {
      if ((prayer || reading || kinds.contains(kind)) && at.isAfter(now.add(const Duration(minutes: 1)))) {
        due.add(_Due(kind, at, title, body, prayer: prayer, reading: reading));
      }
    }

    // Every few hours from the last reading, back to where the reader stopped, for the next two days.
    final last = log?.last;
    final lastAt = log?.lastAt;
    if (reading && last != null && lastAt != null) {
      final book = last['title'].toString();
      final chapter = (last['chapter_title'] ?? '').toString();
      final body = chapter.isEmpty ? t('rem_read_body_book', {'book': book}) : t('rem_read_body', {'book': book, 'chapter': chapter});
      var at = lastAt.add(readingEvery);
      final end = DateTime.now().add(const Duration(days: 2));
      var count = 0;
      while (at.isBefore(end) && count < 8) {
        final local = at.toLocal();
        if (local.hour >= quietUntil && local.hour < quietFrom) {
          add(ReminderKind.hourly, at.toUtc(), t('rem_read_title'), body, reading: true);
          count++;
        }
        at = at.add(readingEvery);
      }
    }

    final today = calculator.localDate(now);
    for (var offset = -1; offset < _days; offset++) {
      final date = today.add(Duration(days: offset));
      final day = dayFor(date)!;
      final next = dayFor(date.add(const Duration(days: 1)))!;
      final night = next.fajr.difference(day.maghrib);
      if (adhan) {
        // Worked out from the reader's own city, so it sounds at their local prayer time wherever they live.
        for (final (key, at) in [('fajr', day.fajr), ('dhuhr', day.dhuhr), ('asr', day.asr), ('maghrib', day.maghrib), ('isha', day.isha)]) {
          add(ReminderKind.afterFajr, at, t('prayer_$key'), t('adhan_body', {'city': city?.name ?? ''}), prayer: true);
        }
      }
      add(ReminderKind.afterFajr, day.fajr.add(const Duration(minutes: 15)), t('rem_fajr_title'), t('rem_fajr_body'));
      add(ReminderKind.evening, day.asr.add(const Duration(minutes: 15)), t('rem_evening_title'), t('rem_evening_body'));
      // The last third of the night, from Maghrib to the next Fajr.
      add(ReminderKind.tahajjud, day.maghrib.add(night * 2 ~/ 3), t('rem_tahajjud_title'), t('rem_tahajjud_body'));
      if (date.weekday == DateTime.friday) {
        add(ReminderKind.friday, day.sunrise.add(const Duration(hours: 1)), t('rem_friday_title'), t('rem_friday_body'));
      }
      if (date.weekday == DateTime.sunday || date.weekday == DateTime.wednesday) {
        final tomorrow = t(date.weekday == DateTime.sunday ? 'day_monday' : 'day_thursday');
        add(ReminderKind.fasting, day.isha.add(const Duration(minutes: 30)), t('rem_fast_title'), t('rem_fast_body', {'day': tomorrow}));
      }
    }

    // Hourly dhikr follows the phone's own clock, so it suits wherever the reader is.
    final local = DateTime.now();
    for (var offset = 0; offset < _days; offset++) {
      final date = DateTime(local.year, local.month, local.day + offset);
      for (var hour = firstHour; hour <= lastHour; hour++) {
        final phrase = hour % 5;
        add(ReminderKind.hourly, DateTime(date.year, date.month, date.day, hour).toUtc(), t('rem_hourly_title'), t('rem_dhikr_$phrase'));
      }
    }
    return due;
  }

  /// Made by MainActivity on Android with the adhan as its sound, so the sound cannot be lost.
  static const _adhanChannel = 'tz.or.iqraa.adhan.sound';
  static const _chapterId = 900001;

  /// The adhan sound plays once and stops when the reader taps Stop, swipes it away or opens it.
  NotificationDetails _adhanDetails(String language) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _adhanChannel,
        Strings.of(language, 'channel_adhan'),
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_notification',
        sound: const RawResourceAndroidNotificationSound('adhan_short'),
        category: AndroidNotificationCategory.reminder,
        timeoutAfter: 60000,
        actions: [AndroidNotificationAction('stop', Strings.of(language, 'stop'), cancelNotification: true)],
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, sound: 'adhan_short.caf'),
    );
  }

  NotificationDetails _readingDetails(String language) {
    return NotificationDetails(
      android: AndroidNotificationDetails('tz.or.iqraa.reading', Strings.of(language, 'channel_reading'), icon: 'ic_notification'),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
  }

  NotificationDetails _details(ReminderKind kind, String language) {
    final (channel, key, importance) = switch (kind) {
      ReminderKind.tahajjud => ('tz.or.iqraa.tahajjud', 'channel_tahajjud', Importance.high),
      ReminderKind.hourly => ('tz.or.iqraa.dhikr', 'channel_dhikr', Importance.defaultImportance),
      _ => ('tz.or.iqraa.reminders', 'channel_reminders', Importance.defaultImportance),
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(channel, Strings.of(language, key), importance: importance, priority: importance == Importance.high ? Priority.high : Priority.defaultPriority, icon: 'ic_notification'),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
  }
}

class _Due {
  const _Due(this.kind, this.at, this.title, this.body, {this.prayer = false, this.reading = false});

  final ReminderKind kind;
  final DateTime at;
  final String title;
  final String body;
  final bool prayer;
  final bool reading;
}
