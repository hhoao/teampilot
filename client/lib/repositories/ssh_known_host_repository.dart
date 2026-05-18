import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class SshKnownHostRepository {
  Future<Map<String, String>> loadAll();
  Future<String?> findFingerprint(String hostIdentifier, String keyType);
  Future<void> saveFingerprint(
    String hostIdentifier,
    String keyType,
    String fingerprintHex,
  );
  Future<void> removeFingerprint(String hostIdentifier, String keyType);
}

class SharedPrefsSshKnownHostRepository implements SshKnownHostRepository {
  const SharedPrefsSshKnownHostRepository(this._preferences);

  static const _key = 'flashskyai.known_hosts.v1';

  final SharedPreferences _preferences;

  Map<String, String> _decode() {
    final stored = _preferences.getString(_key);
    if (stored == null || stored.isEmpty) return {};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry('$k', '$v'));
    } on FormatException {
      return {};
    }
  }

  Future<void> _encode(Map<String, String> data) async {
    if (data.isEmpty) {
      await _preferences.remove(_key);
    } else {
      await _preferences.setString(_key, jsonEncode(data));
    }
  }

  @override
  Future<Map<String, String>> loadAll() async => _decode();

  @override
  Future<String?> findFingerprint(String hostIdentifier, String keyType) async {
    final data = _decode();
    return data['$hostIdentifier::$keyType'];
  }

  @override
  Future<void> saveFingerprint(
    String hostIdentifier,
    String keyType,
    String fingerprintHex,
  ) async {
    final data = _decode();
    data['$hostIdentifier::$keyType'] = fingerprintHex;
    await _encode(data);
  }

  @override
  Future<void> removeFingerprint(String hostIdentifier, String keyType) async {
    final data = _decode();
    data.remove('$hostIdentifier::$keyType');
    await _encode(data);
  }
}

class InMemorySshKnownHostRepository implements SshKnownHostRepository {
  final Map<String, String> _entries = {};

  @override
  Future<Map<String, String>> loadAll() async => Map.of(_entries);

  @override
  Future<String?> findFingerprint(String hostIdentifier, String keyType) async {
    return _entries['$hostIdentifier::$keyType'];
  }

  @override
  Future<void> saveFingerprint(
    String hostIdentifier,
    String keyType,
    String fingerprintHex,
  ) async {
    _entries['$hostIdentifier::$keyType'] = fingerprintHex;
  }

  @override
  Future<void> removeFingerprint(String hostIdentifier, String keyType) async {
    _entries.remove('$hostIdentifier::$keyType');
  }
}
