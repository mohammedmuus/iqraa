import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'session.dart';
import 'strings.dart';

/// Tells the reader when someone in one of their groups passes their dhikr total for the week.
/// The phone asks the server when the app opens and about once an hour in the background, then
/// compares the answer with what it saw last time.
class Rivals extends ChangeNotifier {
  Rivals(this.api, this.session);

  /// Also listed under BGTaskSchedulerPermittedIdentifiers in ios/Runner/Info.plist.
  static const task = 'tz.or.iqraa.rivals';
  static const _keyName = 'rivals_key';
  static const _seenKey = 'rivals_seen';
  static const _onKey = 'rivals_on';

  /// Notification ids start above the range the reminders use.
  static const _firstId = 1000;

  /// Readable after the phone is first unlocked, so the background check works while it is locked.
  static const _store = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

  final Api api;
  final Session session;
  bool enabled = true;

  Future<void> load() async {
    enabled = (await SharedPreferences.getInstance()).getBool(_onKey) ?? true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_onKey, value);
    if (value) {
      await sync();
    } else {
      await stop();
    }
  }

  /// Runs when the app opens or comes back to the front, and after the reader joins or leaves a group.
  Future<void> sync() async {
    if (!enabled || !session.signedIn) {
      return;
    }
    try {
      var key = await _store.read(key: _keyName);
      if (key == null || key.isEmpty) {
        final data = await api.post('dhikr/rivals/key', auth: true);
        key = (data as Map)['key'].toString();
        await _store.write(key: _keyName, value: key);
      }
      final groups = await check(api, key);
      if (groups == 0) {
        await Workmanager().cancelByUniqueName(task);
      } else {
        await Workmanager().registerPeriodicTask(
          task,
          task,
          frequency: const Duration(hours: 1),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      }
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403) {
        await _store.delete(key: _keyName);
      }
    }
  }

  /// Stops the background check and forgets this phone's key. Runs on sign out and when switched off.
  Future<void> stop() async {
    await Workmanager().cancelByUniqueName(task);
    await _store.delete(key: _keyName);
    await (await SharedPreferences.getInstance()).remove(_seenKey);
  }

  /// Asks the server who is ahead in each group, notifies about anyone who was not ahead last time, and
  /// returns how many groups the reader is in. The first check of a week, or of a new group, only takes note.
  static Future<int> check(Api api, String key) async {
    final data = Map<String, dynamic>.from(await api.get('dhikr/rivals', headers: {'X-Rivals-Key': key}) as Map);
    final prefs = await SharedPreferences.getInstance();
    final week = data['week_start'].toString();
    Map<String, dynamic> seen;
    try {
      seen = Map<String, dynamic>.from(jsonDecode(prefs.getString(_seenKey) ?? '{}') as Map);
    } on FormatException {
      seen = {};
    }
    final before = seen['week'] == week ? Map<String, dynamic>.from(seen['groups'] as Map? ?? const {}) : const <String, dynamic>{};
    final firstLook = seen['week'] != week;
    final language = prefs.getString('language') ?? 'en';
    final now = <String, List<String>>{};
    final groups = [for (final row in (data['groups'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final id = group['id'].toString();
      final ahead = [for (final row in (group['ahead'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
      now[id] = [for (final row in ahead) row['key'].toString()];
      final previous = before[id] as List?;
      if (firstLook || previous == null) {
        continue;
      }
      final passed = [for (final row in ahead) if (!previous.contains(row['key'])) row];
      if (passed.isNotEmpty) {
        await _notify(_firstId + index, language, group, passed);
      }
    }
    await prefs.setString(_seenKey, jsonEncode({'week': week, 'groups': now}));
    return groups.length;
  }

  static Future<void> _notify(int id, String language, Map<String, dynamic> group, List<Map<String, dynamic>> passed) async {
    String t(String key, [Map<String, Object> values = const {}]) => Strings.of(language, key, values);
    final first = passed.first;
    final title = passed.length == 1
        ? t('rival_title', {'name': first['name'].toString()})
        : t('rival_title_many', {'name': first['name'].toString(), 'n': passed.length - 1});
    final body = t('rival_body', {'group': group['name'].toString(), 'theirs': first['total'] ?? 0, 'mine': group['you'] ?? 0});
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestSoundPermission: false, requestBadgePermission: false),
      ),
    );
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('tz.or.iqraa.groups', t('channel_groups'), icon: 'ic_notification'),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}

/// Runs the hourly group check in the background, without the app open.
@pragma('vm:entry-point')
void rivalsDispatcher() {
  Workmanager().executeTask((name, input) async {
    if (name != Rivals.task) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await Rivals._store.read(key: Rivals._keyName);
      if ((prefs.getBool(Rivals._onKey) ?? true) && key != null && key.isNotEmpty) {
        final api = Api(Session());
        await api.init();
        await Rivals.check(api, key);
      }
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403) {
        // The session ended on the server, so this phone stops checking until the reader signs in again.
        await Rivals._store.delete(key: Rivals._keyName);
        await Workmanager().cancelByUniqueName(Rivals.task);
      }
    }
    return true;
  });
}
