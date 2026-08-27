import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SshCredentialStore {
  Future<String?> loadPassword(String profileId);
  Future<void> savePassword(String profileId, String password);
  Future<String?> loadPrivateKey(String profileId);
  Future<void> savePrivateKey(String profileId, String privateKey);
  Future<String?> loadPrivateKeyPassphrase(String profileId);
  Future<void> savePrivateKeyPassphrase(String profileId, String passphrase);
  Future<String?> loadDevicePrivateKey();
  Future<void> saveDevicePrivateKey(String privateKey);
  Future<String?> loadRelayGrant(String profileId);
  Future<void> saveRelayGrant(String profileId, String grant);
  Future<void> deleteAll(String profileId);
}

abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}

class SecureSshCredentialStore implements SshCredentialStore {
  const SecureSshCredentialStore(this._store);

  static const _prefix = 'flashskyai.ssh_creds.v1';

  final SecureKeyValueStore _store;

  String _key(String profileId, String field) => '$_prefix.$profileId.$field';

  String get _deviceKey => '$_prefix.connect.device.privateKey';

  @override
  Future<String?> loadPassword(String profileId) {
    return _store.read(_key(profileId, 'password'));
  }

  @override
  Future<void> savePassword(String profileId, String password) {
    return _store.write(_key(profileId, 'password'), password);
  }

  @override
  Future<String?> loadPrivateKey(String profileId) {
    return _store.read(_key(profileId, 'privateKey'));
  }

  @override
  Future<void> savePrivateKey(String profileId, String privateKey) {
    return _store.write(_key(profileId, 'privateKey'), privateKey);
  }

  @override
  Future<String?> loadPrivateKeyPassphrase(String profileId) {
    return _store.read(_key(profileId, 'passphrase'));
  }

  @override
  Future<void> savePrivateKeyPassphrase(String profileId, String passphrase) {
    return _store.write(_key(profileId, 'passphrase'), passphrase);
  }

  @override
  Future<String?> loadDevicePrivateKey() => _store.read(_deviceKey);

  @override
  Future<void> saveDevicePrivateKey(String privateKey) =>
      _store.write(_deviceKey, privateKey);

  @override
  Future<String?> loadRelayGrant(String profileId) =>
      _store.read(_key(profileId, 'relayGrant'));

  @override
  Future<void> saveRelayGrant(String profileId, String grant) =>
      _store.write(_key(profileId, 'relayGrant'), grant);

  @override
  Future<void> deleteAll(String profileId) async {
    await _store.delete(_key(profileId, 'password'));
    await _store.delete(_key(profileId, 'privateKey'));
    await _store.delete(_key(profileId, 'passphrase'));
    await _store.delete(_key(profileId, 'relayGrant'));
  }
}

class SharedPrefsSshCredentialStore implements SshCredentialStore {
  const SharedPrefsSshCredentialStore(this._preferences);

  static const _prefix = 'flashskyai.ssh_creds.v1';

  final SharedPreferences _preferences;

  String _key(String profileId, String field) => '$_prefix.$profileId.$field';

  String get _deviceKey => '$_prefix.connect.device.privateKey';

  @override
  Future<String?> loadPassword(String profileId) async {
    return _preferences.getString(_key(profileId, 'password'));
  }

  @override
  Future<void> savePassword(String profileId, String password) async {
    await _preferences.setString(_key(profileId, 'password'), password);
  }

  @override
  Future<String?> loadPrivateKey(String profileId) async {
    return _preferences.getString(_key(profileId, 'privateKey'));
  }

  @override
  Future<void> savePrivateKey(String profileId, String privateKey) async {
    await _preferences.setString(_key(profileId, 'privateKey'), privateKey);
  }

  @override
  Future<String?> loadPrivateKeyPassphrase(String profileId) async {
    return _preferences.getString(_key(profileId, 'passphrase'));
  }

  @override
  Future<void> savePrivateKeyPassphrase(
    String profileId,
    String passphrase,
  ) async {
    await _preferences.setString(_key(profileId, 'passphrase'), passphrase);
  }

  @override
  Future<String?> loadDevicePrivateKey() async =>
      _preferences.getString(_deviceKey);

  @override
  Future<void> saveDevicePrivateKey(String privateKey) async {
    await _preferences.setString(_deviceKey, privateKey);
  }

  @override
  Future<String?> loadRelayGrant(String profileId) async =>
      _preferences.getString(_key(profileId, 'relayGrant'));

  @override
  Future<void> saveRelayGrant(String profileId, String grant) async {
    await _preferences.setString(_key(profileId, 'relayGrant'), grant);
  }

  @override
  Future<void> deleteAll(String profileId) async {
    await _preferences.remove(_key(profileId, 'password'));
    await _preferences.remove(_key(profileId, 'privateKey'));
    await _preferences.remove(_key(profileId, 'passphrase'));
    await _preferences.remove(_key(profileId, 'relayGrant'));
  }
}

class InMemorySshCredentialStore implements SshCredentialStore {
  final _passwords = <String, String>{};
  final _privateKeys = <String, String>{};
  final _passphrases = <String, String>{};
  String? _devicePrivateKey;
  final _relayGrants = <String, String>{};

  @override
  Future<String?> loadPassword(String profileId) async => _passwords[profileId];

  @override
  Future<void> savePassword(String profileId, String password) async {
    _passwords[profileId] = password;
  }

  @override
  Future<String?> loadPrivateKey(String profileId) async =>
      _privateKeys[profileId];

  @override
  Future<void> savePrivateKey(String profileId, String privateKey) async {
    _privateKeys[profileId] = privateKey;
  }

  @override
  Future<String?> loadPrivateKeyPassphrase(String profileId) async =>
      _passphrases[profileId];

  @override
  Future<void> savePrivateKeyPassphrase(
    String profileId,
    String passphrase,
  ) async {
    _passphrases[profileId] = passphrase;
  }

  @override
  Future<String?> loadDevicePrivateKey() async => _devicePrivateKey;

  @override
  Future<void> saveDevicePrivateKey(String privateKey) async {
    _devicePrivateKey = privateKey;
  }

  @override
  Future<String?> loadRelayGrant(String profileId) async =>
      _relayGrants[profileId];

  @override
  Future<void> saveRelayGrant(String profileId, String grant) async {
    _relayGrants[profileId] = grant;
  }

  @override
  Future<void> deleteAll(String profileId) async {
    _passwords.remove(profileId);
    _privateKeys.remove(profileId);
    _passphrases.remove(profileId);
    _relayGrants.remove(profileId);
  }
}
