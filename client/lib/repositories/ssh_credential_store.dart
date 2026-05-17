import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SshCredentialStore {
  Future<String?> loadPassword(String profileId);
  Future<void> savePassword(String profileId, String password);
  Future<String?> loadPrivateKey(String profileId);
  Future<void> savePrivateKey(String profileId, String privateKey);
  Future<String?> loadPrivateKeyPassphrase(String profileId);
  Future<void> savePrivateKeyPassphrase(String profileId, String passphrase);
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
  Future<void> deleteAll(String profileId) async {
    await _store.delete(_key(profileId, 'password'));
    await _store.delete(_key(profileId, 'privateKey'));
    await _store.delete(_key(profileId, 'passphrase'));
  }
}

class SharedPrefsSshCredentialStore implements SshCredentialStore {
  const SharedPrefsSshCredentialStore(this._preferences);

  static const _prefix = 'flashskyai.ssh_creds.v1';

  final SharedPreferences _preferences;

  String _key(String profileId, String field) => '$_prefix.$profileId.$field';

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
  Future<void> deleteAll(String profileId) async {
    await _preferences.remove(_key(profileId, 'password'));
    await _preferences.remove(_key(profileId, 'privateKey'));
    await _preferences.remove(_key(profileId, 'passphrase'));
  }
}

class InMemorySshCredentialStore implements SshCredentialStore {
  final _passwords = <String, String>{};
  final _privateKeys = <String, String>{};
  final _passphrases = <String, String>{};

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
  Future<void> deleteAll(String profileId) async {
    _passwords.remove(profileId);
    _privateKeys.remove(profileId);
    _passphrases.remove(profileId);
  }
}
