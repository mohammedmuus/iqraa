import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import 'json_work.dart';
import 'session.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.fields = const {}, this.code = '', this.address = '']);

  /// A connection problem the app words itself, in the reader's language. [code] is a key in strings.dart.
  ApiException.local(String code, {String address = ''}) : this(0, code, const {}, code, address);

  final int status;
  final String message;
  final Map<String, String> fields;
  final String code;
  final String address;

  bool get isOffline => status == 0;

  factory ApiException.from(int status, Object? data) {
    if (data is Map) {
      final fields = <String, String>{};
      String? detail;
      data.forEach((key, value) {
        final text = value is List ? value.join(' ') : value.toString();
        if (key == 'detail' || key == 'non_field_errors') {
          detail = text;
        } else if (key != 'code') {
          fields[key.toString()] = text;
        }
      });
      final message = detail ?? (fields.isNotEmpty ? fields.values.first : null);
      final code = (data['code'] ?? '').toString();
      return message == null ? ApiException(status, 'generic', const {}, 'generic') : ApiException(status, message, fields, code);
    }
    if (status == 429) {
      return ApiException(status, 'throttled', const {}, 'throttled');
    }
    return ApiException(status, 'generic', const {}, 'generic');
  }

  @override
  String toString() => message;
}

class Api {
  Api(this.session);

  final Session session;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20);
  String _agent = 'Iqraa-Android/1.0.0';

  /// Hosts the library server approves for recitation audio, sent with the app settings.
  Set<String> audioHosts = const {};

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    final system = Platform.isIOS ? 'iOS' : 'Android';
    _agent = 'Iqraa-$system/${info.version} ($system ${Platform.operatingSystemVersion})';
    _client.userAgent = _agent;
  }

  Future<dynamic> get(String path, {bool auth = false, Map<String, String>? query, Map<String, String>? headers}) {
    return _send('GET', path, auth: auth, query: query, headers: headers);
  }

  Future<dynamic> post(String path, {Object? body, bool auth = false, Map<String, String>? headers}) {
    return _send('POST', path, body: body, auth: auth, headers: headers);
  }

  Future<dynamic> patch(String path, {Object? body, bool auth = false}) {
    return _send('PATCH', path, body: body, auth: auth);
  }

  Future<dynamic> put(String path, {Object? body, bool auth = false}) {
    return _send('PUT', path, body: body, auth: auth);
  }

  Future<dynamic> delete(String path, {bool auth = false}) {
    return _send('DELETE', path, auth: auth);
  }

  Future<dynamic> _send(String method, String path, {Object? body, bool auth = false, Map<String, String>? query, Map<String, String>? headers, bool retried = false}) async {
    if (AppConfig.apiBase.isEmpty) {
      throw ApiException.local('no_server');
    }
    final slashed = path.endsWith('/') ? path : '$path/';
    final uri = Uri.parse('${AppConfig.apiBase}/api/v1/$slashed').replace(queryParameters: query == null || query.isEmpty ? null : query);
    String? token;
    if (auth) {
      token = await session.accessToken(this);
      if (token == null) {
        throw ApiException(401, 'sign_in_again', const {}, 'sign_in_again');
      }
    }
    try {
      final request = await _client.openUrl(method, uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      headers?.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(const Duration(seconds: 30));
      _checkPin(uri, response.certificate);
      final text = await response.transform(utf8.decoder).join();
      final data = text.isEmpty ? null : await _decode(text);
      if (response.statusCode == 401 && auth && !retried) {
        if (await session.refreshTokens(this)) {
          return await _send(method, path, body: body, auth: auth, query: query, headers: headers, retried: true);
        }
        await session.clear();
      }
      if (response.statusCode >= 400) {
        throw ApiException.from(response.statusCode, data);
      }
      return data;
    } on ApiException {
      rethrow;
    } on HandshakeException {
      throw ApiException.local('secure');
    } on SocketException {
      throw _unreachable();
    } on TimeoutException {
      throw ApiException.local('timeout');
    } on HttpException {
      throw ApiException.local('interrupted');
    }
  }

  /// Large replies, such as a long chapter, are decoded off the main thread so the screen keeps moving.
  Future<Object?> _decode(String text) async {
    try {
      return await decodeJson(text);
    } on FormatException {
      return null;
    }
  }

  /// Pins are base64 SHA-256 hashes of the server's public key (SubjectPublicKeyInfo), the same value
  /// `python manage.py app_pins` prints. A pin survives certificate renewals that keep the same key.
  void _checkPin(Uri uri, X509Certificate? certificate) {
    final pins = AppConfig.pins;
    if (uri.scheme != 'https' || pins.isEmpty) {
      return;
    }
    final pin = certificate == null ? null : spkiPin(certificate.der);
    if (pin == null || !pins.contains(pin)) {
      throw ApiException.local('secure');
    }
  }

  /// Debug builds name the address they tried, so a phone pointed at the wrong computer is easy to spot.
  ApiException _unreachable() => kDebugMode ? ApiException.local('unreachable', address: AppConfig.apiBase) : ApiException.local('offline');

  /// Saves a file for offline use. Only files on the API server or on an approved audio host over https are fetched.
  Future<void> download(String url, File target) async {
    final uri = Uri.tryParse(url);
    final base = Uri.parse(AppConfig.apiBase);
    final sameServer = uri != null && uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port;
    final approved = uri != null && uri.scheme == 'https' && audioHosts.contains(uri.host);
    if (!sameServer && !approved) {
      throw ApiException.local('generic');
    }
    final part = File('${target.path}.part');
    try {
      final request = await _client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (sameServer) {
        _checkPin(uri, response.certificate);
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw ApiException.from(response.statusCode, null);
      }
      await part.parent.create(recursive: true);
      await response.pipe(part.openWrite());
      await part.rename(target.path);
    } on HandshakeException {
      throw ApiException.local('secure');
    } on SocketException {
      throw _unreachable();
    } on TimeoutException {
      throw ApiException.local('timeout');
    } on HttpException {
      throw ApiException.local('interrupted');
    } finally {
      if (await part.exists()) {
        await part.delete();
      }
    }
  }
}

String? spkiPin(Uint8List der) {
  (int, int) field(int at) {
    var index = at + 1;
    var length = der[index++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var step = 0; step < count; step++) {
        length = (length << 8) | der[index++];
      }
    }
    return (index, length);
  }

  try {
    var (at, _) = field(0);
    (at, _) = field(at);
    if (der[at] == 0xA0) {
      final (start, length) = field(at);
      at = start + length;
    }
    for (var skip = 0; skip < 5; skip++) {
      final (start, length) = field(at);
      at = start + length;
    }
    final (start, length) = field(at);
    return base64.encode(sha256.convert(der.sublist(at, start + length)).bytes);
  } on RangeError {
    return null;
  }
}
