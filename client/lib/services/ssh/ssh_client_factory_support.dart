import 'dart:async';
import 'dart:collection';

import '../../repositories/ssh_credential_store.dart';

/// Bounds unauthenticated handshakes per dial target.
class SshHandshakeGate {
  SshHandshakeGate(this.maxConcurrent);

  final int maxConcurrent;
  final Map<String, int> _active = {};
  final Map<String, Queue<Completer<void>>> _waiting = {};

  Future<void> acquire(String key) {
    final active = _active[key] ?? 0;
    if (active < maxConcurrent) {
      _active[key] = active + 1;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.putIfAbsent(key, Queue<Completer<void>>.new).add(waiter);
    return waiter.future;
  }

  void release(String key) {
    final queue = _waiting[key];
    if (queue != null && queue.isNotEmpty) {
      queue.removeFirst().complete();
      return;
    }
    final active = (_active[key] ?? 1) - 1;
    if (active <= 0) {
      _active.remove(key);
      _waiting.remove(key);
    } else {
      _active[key] = active;
    }
  }
}

/// Overlays one connection test's form credentials without persisting them.
class SshCredentialOverrideStore implements SshCredentialStore {
  SshCredentialOverrideStore({
    required SshCredentialStore base,
    required this.profileId,
    this.password,
    this.privateKey,
    this.privateKeyPassphrase,
  }) : _base = base;

  final SshCredentialStore _base;
  final String profileId;
  final String? password;
  final String? privateKey;
  final String? privateKeyPassphrase;

  bool _hasOverride(String? value) => value != null && value.isNotEmpty;

  @override
  Future<String?> loadPassword(String id) async =>
      id == profileId && _hasOverride(password)
      ? password
      : _base.loadPassword(id);

  @override
  Future<String?> loadPrivateKey(String id) async =>
      id == profileId && _hasOverride(privateKey)
      ? privateKey
      : _base.loadPrivateKey(id);

  @override
  Future<String?> loadPrivateKeyPassphrase(String id) async =>
      id == profileId && _hasOverride(privateKeyPassphrase)
      ? privateKeyPassphrase
      : _base.loadPrivateKeyPassphrase(id);

  @override
  Future<void> savePassword(String profileId, String password) =>
      _base.savePassword(profileId, password);

  @override
  Future<void> savePrivateKey(String profileId, String privateKey) =>
      _base.savePrivateKey(profileId, privateKey);

  @override
  Future<void> savePrivateKeyPassphrase(String profileId, String passphrase) =>
      _base.savePrivateKeyPassphrase(profileId, passphrase);

  @override
  Future<String?> loadDevicePrivateKey() => _base.loadDevicePrivateKey();

  @override
  Future<void> saveDevicePrivateKey(String privateKey) =>
      _base.saveDevicePrivateKey(privateKey);

  @override
  Future<String?> loadRelayGrant(String profileId) =>
      _base.loadRelayGrant(profileId);

  @override
  Future<void> saveRelayGrant(String profileId, String grant) =>
      _base.saveRelayGrant(profileId, grant);

  @override
  Future<void> deleteAll(String profileId) => _base.deleteAll(profileId);
}
