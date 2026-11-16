import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'cities.dart';
import 'prayer_times.dart';
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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('reminders_on') ?? false;
    promptDismissed = prefs.getBool('reminders_prompt_dismissed') ?? false;
    adhan = prefs.getBool('reminders_adhan') ?? false;
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
        notificationDetails: item.prayer ? _adhanDetails(language) : _details(item.kind, language),
        androidScheduleMode: item.prayer && exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  List<_Due> _plan(PrayerTimes calculator, DateTime now, String language) {
    String t(String key, [Map<String, Object> values = const {}]) => Strings.of(language, key, values);
    final due = <_Due>[];
    void add(ReminderKind kind, DateTime at, String title, String body, {bool prayer = false}) {
      if ((prayer || kinds.contains(kind)) && at.isAfter(now.add(const Duration(minutes: 1)))) {
        due.add(_Due(kind, at, title, body, prayer: prayer));
      }
    }

    final today = calculator.localDate(now);
    for (var offset = -1; offset < _days; offset++) {
      final date = today.add(Duration(days: offset));
      final day = calculator.forDate(date);
      final next = calculator.forDate(date.add(const Duration(days: 1)));
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

  static const _adhanChannel = 'tz.or.iqraa.adhan';
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
  const _Due(this.kind, this.at, this.title, this.body, {this.prayer = false});

  final ReminderKind kind;
  final DateTime at;
  final String title;
  final String body;
  final bool prayer;
}
