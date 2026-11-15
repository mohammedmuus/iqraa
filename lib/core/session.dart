import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Sign in state. The refresh token lives in the phone's secure storage; the access token only in memory.
class Session extends ChangeNotifier {
  static const _refreshKey = 'refresh';
  static const _biometricKey = 'biometric';
  static const _emailKey = 'last_email';

  final FlutterSecureStorage _store = const FlutterSecureStorage();

  String? _access;
  DateTime _accessExpires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<bool>? _refreshing;

  bool signedIn = false;
  bool biometricEnabled = false;
  bool locked = false;
  DateTime? backgroundedAt;
  Map<String, dynamic>? profile;

  Future<void> load() async {
    final refresh = await _read(_refreshKey);
    biometricEnabled = await _read(_biometricKey) == '1';
    signedIn = refresh != null && refresh.isNotEmpty;
    locked = signedIn && biometricEnabled;
    notifyListeners();
  }

  Future<String?> lastEmail() => _read(_emailKey);

  Future<void> rememberEmail(String email) => _store.write(key: _emailKey, value: email);

  Future<void> setBiometric(bool enabled) async {
    biometricEnabled = enabled;
    await _store.write(key: _biometricKey, value: enabled ? '1' : '0');
    notifyListeners();
  }

  void lock() {
    if (signedIn && biometricEnabled) {
      locked = true;
      _access = null;
      notifyListeners();
    }
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  /// Ends this phone's session on the server too, then forgets the tokens.
  Future<void> signOut(Api api) async {
    final refresh = await _read(_refreshKey);
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await api.post('auth/sign-out', body: {'refresh': refresh});
      } on ApiException {
        // Signing out on the phone still goes ahead when the server cannot be reached.
      }
    }
    await clear();
  }

  Future<void> saveTokens(Map<String, dynamic> data) async {
    _access = data['access'] as String?;
    locked = false;
    final seconds = (data['access_expires_in'] as num?)?.toInt() ?? 600;
    _accessExpires = DateTime.now().add(Duration(seconds: seconds - 30));
    await _store.write(key: _refreshKey, value: data['refresh'] as String?);
    signedIn = true;
    notifyListeners();
  }

  Future<String?> accessToken(Api api) async {
    if (_access != null && DateTime.now().isBefore(_accessExpires)) {
      return _access;
    }
    final ok = await refreshTokens(api);
    return ok ? _access : null;
  }

  Future<bool> refreshTokens(Api api) {
    return _refreshing ??= _rotate(api).whenComplete(() => _refreshing = null);
  }

  Future<bool> _rotate(Api api) async {
    final refresh = await _read(_refreshKey);
    if (refresh == null || refresh.isEmpty) {
      return false;
    }
    try {
      final data = await api.post('auth/refresh', body: {'refresh': refresh});
      await saveTokens(Map<String, dynamic>.from(data as Map));
      return true;
    } on ApiException catch (error) {
      if (error.isOffline) {
        rethrow;
      }
      if (error.status == 401) {
        await clear();
      }
      return false;
    }
  }

  Future<String?> refreshToken() => _read(_refreshKey);

  void setProfile(Map<String, dynamic>? data) {
    profile = data;
    notifyListeners();
  }

  Future<void> clear() async {
    _access = null;
    profile = null;
    signedIn = false;
    locked = false;
    await _store.delete(key: _refreshKey);
    notifyListeners();
  }

  Future<String?> _read(String key) async {
    try {
      return await _store.read(key: key);
    } on Exception {
      await _store.deleteAll();
      return null;
    }
  }
}
