import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_known_host_repository.dart';

typedef SshClientConnector =
    Future<SSHClient> Function(
      SshProfile profile, {
      Duration timeout,
    });

class _PooledConnection {
  _PooledConnection({
    required this.client,
    required this.hostIdentifier,
    required this.ready,
  });

  final SSHClient client;
  final String hostIdentifier;
  final Future<void> ready;
}

class HostKeyPromptInfo {
  HostKeyPromptInfo({
    required this.profile,
    required this.keyType,
    required this.fingerprintHex,
    required this.fingerprintBase64,
    required this.isMismatch,
    this.previousFingerprintHex,
  });

  final SshProfile profile;
  final String keyType;
  final String fingerprintHex;
  final String fingerprintBase64;
  final bool isMismatch;
  final String? previousFingerprintHex;
}

class SshClientFactory {
  SshClientFactory({
    required SshCredentialStore credentialStore,
    required SshKnownHostRepository knownHostRepository,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
    SshClientConnector? connector,
  }) : _credentialStore = credentialStore,
       _hostKeyTrustPolicy = SshHostKeyTrustPolicy(
         knownHostRepository: knownHostRepository,
         onHostKeyPrompt: onHostKeyPrompt,
         onHostKeyPersist: onHostKeyPersist,
       ),
       _connector = connector;

  final SshCredentialStore _credentialStore;
  final SshHostKeyTrustPolicy _hostKeyTrustPolicy;
  final SshClientConnector? _connector;
  final Map<String, _PooledConnection> _pool = {};

  /// Returns a shared, authenticated [SSHClient] for [profile].
  ///
  /// One pooled connection is kept per profile id until [disconnectProfile] or
  /// [disconnectAll] is called, or the remote host identity changes.
  Future<SSHClient> clientFor(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final cached = _pool[profile.id];
    if (cached != null) {
      if (cached.client.isClosed) {
        _pool.remove(profile.id);
      } else if (cached.hostIdentifier == profile.hostIdentifier) {
        await cached.ready;
        return cached.client;
      } else {
        cached.client.close();
        _pool.remove(profile.id);
      }
    }

    final client = await (_connector ?? createClient)(profile, timeout: timeout);
    final ready = client.authenticated;
    _pool[profile.id] = _PooledConnection(
      client: client,
      hostIdentifier: profile.hostIdentifier,
      ready: ready,
    );
    await ready;
    return client;
  }

  void disconnectProfile(String profileId) {
    final cached = _pool.remove(profileId);
    if (cached != null && !cached.client.isClosed) {
      cached.client.close();
    }
  }

  void disconnectAll() {
    for (final cached in _pool.values) {
      if (!cached.client.isClosed) {
        cached.client.close();
      }
    }
    _pool.clear();
  }

  static String fingerprintToHex(Uint8List fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(fingerprint[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String fingerprintToBase64(Uint8List fingerprint) =>
      base64.encode(fingerprint);

  Future<SSHClient> createClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: timeout,
    );

    Future<bool> hostKeyVerifier(String keyType, Uint8List fingerprint) async {
      return _hostKeyTrustPolicy.verify(
        profile: profile,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    }

    switch (profile.authType) {
      case SshAuthType.password:
        final password = await _credentialStore.loadPassword(profile.id) ?? '';
        return SSHClient(
          socket,
          username: profile.username,
          onPasswordRequest: () => password,
          onVerifyHostKey: hostKeyVerifier,
        );
      case SshAuthType.privateKey:
        final privateKey = await _credentialStore.loadPrivateKey(profile.id);
        if (privateKey == null || privateKey.isEmpty) {
          throw StateError('Private key not found for profile ${profile.id}');
        }
        final passphrase = await _credentialStore.loadPrivateKeyPassphrase(
          profile.id,
        );
        final identities = SSHKeyPair.fromPem(
          privateKey,
          passphrase == null || passphrase.isEmpty ? null : passphrase,
        );
        return SSHClient(
          socket,
          username: profile.username,
          identities: identities,
          onVerifyHostKey: hostKeyVerifier,
        );
    }
  }
}

class SshHostKeyTrustPolicy {
  SshHostKeyTrustPolicy({
    required SshKnownHostRepository knownHostRepository,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
  }) : _knownHostRepository = knownHostRepository,
       _onHostKeyPrompt = onHostKeyPrompt,
       _onHostKeyPersist = onHostKeyPersist;

  final SshKnownHostRepository _knownHostRepository;
  final Future<bool> Function(HostKeyPromptInfo)? _onHostKeyPrompt;
  final void Function(String storageKey, String fingerprintHex)?
  _onHostKeyPersist;

  Future<bool> verify({
    required SshProfile profile,
    required String keyType,
    required Uint8List fingerprint,
  }) async {
    final storageKey = '${profile.hostIdentifier}::$keyType';
    final fingerprintHex = SshClientFactory.fingerprintToHex(fingerprint);
    final fingerprintBase64 = SshClientFactory.fingerprintToBase64(fingerprint);
    final existing = await _knownHostRepository.findFingerprint(
      profile.hostIdentifier,
      keyType,
    );

    if (existing == null) {
      if (_onHostKeyPrompt != null) {
        final accepted = await _onHostKeyPrompt(
          HostKeyPromptInfo(
            profile: profile,
            keyType: keyType,
            fingerprintHex: fingerprintHex,
            fingerprintBase64: fingerprintBase64,
            isMismatch: false,
          ),
        );
        if (!accepted) return false;
      }
      await _knownHostRepository.saveFingerprint(
        profile.hostIdentifier,
        keyType,
        fingerprintHex,
      );
      _onHostKeyPersist?.call(storageKey, fingerprintHex);
      return true;
    }

    if (existing == fingerprintHex) return true;

    if (_onHostKeyPrompt == null) return false;
    final accepted = await _onHostKeyPrompt(
      HostKeyPromptInfo(
        profile: profile,
        keyType: keyType,
        fingerprintHex: fingerprintHex,
        fingerprintBase64: fingerprintBase64,
        isMismatch: true,
        previousFingerprintHex: existing,
      ),
    );
    if (!accepted) return false;
    await _knownHostRepository.saveFingerprint(
      profile.hostIdentifier,
      keyType,
      fingerprintHex,
    );
    _onHostKeyPersist?.call(storageKey, fingerprintHex);
    return true;
  }
}
