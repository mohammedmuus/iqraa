import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'cache.dart';
import 'session.dart';

/// Dhikr counts kept on the phone, so counting works without internet or an account. When signed in, whole day
/// totals go to the server, which keeps the higher number, so repeated or late uploads never double count.
class DhikrStore extends ChangeNotifier {
  DhikrStore(this.api, this.cache, this.session);

  static const _countsKey = 'dhikr_counts';
  static const _dirtyKey = 'dhikr_dirty';
  static const _goalKey = 'dhikr_goal';
  static const limit = 100000;

  final Api api;
  final PublicCache cache;
  final Session session;

  List<Map<String, dynamic>> adhkar = const [];
  Map<String, Map<String, int>> _days = {};
  Map<String, dynamic>? profile;

  /// The reader's own daily goal for every dhikr, or null to use each dhikr's suggested goal.
  int? goal;
  bool _dirty = false;
  Timer? _syncSoon;

  static String day([DateTime? when]) {
    final d = when ?? DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int today(String slug) => _days[day()]?[slug] ?? 0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = prefs.getString(_countsKey);
      if (saved != null) {
        _days = {
          for (final entry in (jsonDecode(saved) as Map).entries)
            entry.key.toString(): {for (final c in (entry.value as Map).entries) c.key.toString(): (c.value as num).toInt()},
        };
      }
    } on Object {
      _days = {};
    }
    _dirty = prefs.getBool(_dirtyKey) ?? false;
    goal = prefs.getInt(_goalKey);
    notifyListeners();
  }

  int goalFor(Map<String, dynamic> dhikr) => goal ?? (dhikr['daily_goal'] as num?)?.toInt() ?? 33;

  Future<void> setGoal(int? value) async {
    goal = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    value == null ? await prefs.remove(_goalKey) : await prefs.setInt(_goalKey, value);
  }

  Future<void> loadAdhkar() async {
    final data = await cache.load('dhikr');
    adhkar = [for (final row in (data['adhkar'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
    notifyListeners();
  }

  void add(String slug, [int by = 1]) {
    final key = day();
    final counts = _days.putIfAbsent(key, () => {});
    counts[slug] = ((counts[slug] ?? 0) + by).clamp(0, limit);
    _dirty = true;
    notifyListeners();
    unawaited(_save());
    _syncSoon?.cancel();
    _syncSoon = Timer(const Duration(seconds: 4), () => unawaited(sync()));
  }

  /// Sends the last week's totals and takes the server's figures back for days counted on another phone.
  Future<void> sync() async {
    if (!session.signedIn) {
      return;
    }
    try {
      if (_dirty) {
        final entries = [
          for (final MapEntry(key: date, value: counts) in _days.entries)
            for (final MapEntry(key: slug, value: count) in counts.entries)
              if (count > 0) {'dhikr': slug, 'day': date, 'count': count},
        ];
        if (entries.isNotEmpty) {
          final data = Map<String, dynamic>.from(await api.post('dhikr/counts', body: {'entries': entries}, auth: true) as Map);
          _takeProfile(Map<String, dynamic>.from(data['profile'] as Map));
        }
        _dirty = false;
        await _save();
      } else {
        _takeProfile(Map<String, dynamic>.from(await api.get('dhikr/me', auth: true) as Map));
      }
    } on ApiException {
      return;
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> changes) async {
    final data = Map<String, dynamic>.from(await api.patch('dhikr/me', body: changes, auth: true) as Map);
    _takeProfile(data);
    return data;
  }

  void _takeProfile(Map<String, dynamic> data) {
    profile = data;
    final server = data['today'];
    if (server is Map) {
      final counts = _days.putIfAbsent(day(), () => {});
      server.forEach((slug, value) {
        final count = (value as num).toInt();
        if (count > (counts[slug.toString()] ?? 0)) {
          counts[slug.toString()] = count;
        }
      });
    }
    notifyListeners();
  }

  void forgetAccount() {
    profile = null;
    notifyListeners();
  }

  Future<void> _save() async {
    // Only the last eight days are kept; the server accepts a week back.
    final oldest = day(DateTime.now().subtract(const Duration(days: 8)));
    _days.removeWhere((date, _) => date.compareTo(oldest) < 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_countsKey, jsonEncode(_days));
    await prefs.setBool(_dirtyKey, _dirty);
  }
}
