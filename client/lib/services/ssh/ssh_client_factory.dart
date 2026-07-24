import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import 'ssh_connection_events.dart';

typedef SshClientConnector =
    Future<SSHClient> Function(SshProfile profile, {Duration timeout});

typedef SshProfileTransportClosedHandler =
    void Function(String profileId, Object error, StackTrace stackTrace);

class _PooledConnection {
  _PooledConnection({
    required this.client,
    required this.hostIdentifier,
    required this.ready,
  });

  final SSHClient client;
  final String hostIdentifier;
  final Future<void> ready;
  bool readyCompleted = false;
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
    SshConnectionEvents? events,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
    SshClientConnector? connector,
  }) : _credentialStore = credentialStore,
       _knownHostRepository = knownHostRepository,
       _events = events ?? SshConnectionEvents(),
       _onHostKeyPrompt = onHostKeyPrompt,
       _onHostKeyPersist = onHostKeyPersist,
       _hostKeyTrustPolicy = SshHostKeyTrustPolicy(
         knownHostRepository: knownHostRepository,
         onHostKeyPrompt: onHostKeyPrompt,
         onHostKeyPersist: onHostKeyPersist,
       ),
       _connector = connector;

  final SshCredentialStore _credentialStore;
  final SshKnownHostRepository _knownHostRepository;
  final SshConnectionEvents _events;
  final Future<bool> Function(HostKeyPromptInfo)? _onHostKeyPrompt;
  final void Function(String storageKey, String fingerprintHex)?
  _onHostKeyPersist;
  final SshHostKeyTrustPolicy _hostKeyTrustPolicy;
  final SshClientConnector? _connector;
  final Map<String, _PooledConnection> _pool = {};
  final Map<String, SftpClient> _sftpByProfile = {};
  final Set<SSHClient> _watchedClients = {};
  final _poolChanges = StreamController<String>.broadcast();

  bool hasLiveStorageClient(String profileId) {
    final cached = _pool[profileId];
    return cached != null &&
        !cached.client.isClosed &&
        cached.readyCompleted;
  }

  Stream<String> get storagePoolChanges => _poolChanges.stream;

  void _notifyPoolChange(String profileId) {
    if (!_poolChanges.isClosed) _poolChanges.add(profileId);
  }

  /// Pooled storage-plane client for [profile] (SFTP / file I/O only).
  ///
  /// Interactive session work (PTY, reverse bus tunnels, exec probes) must use
  /// [createMemberClient] via [SshMemberSession.open] instead.
  Future<SSHClient> clientForStorage(
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
        _evictProfile(profile.id, closePooled: true);
      }
    }

    final client = await _connectClient(profile, timeout: timeout);
    final ready = client.authenticated;
    final pooled = _PooledConnection(
      client: client,
      hostIdentifier: profile.hostIdentifier,
      ready: ready,
    );
    _pool[profile.id] = pooled;
    try {
      await ready;
      pooled.readyCompleted = true;
      _notifyPoolChange(profile.id);
    } on Object {
      _evictProfile(profile.id, closePooled: true);
      rethrow;
    }
    return client;
  }

  /// Shared SFTP session for [profile] (reused by all [RemoteFileStore] instances).
  Future<SftpClient> sftpFor(SshProfile profile) async {
    final cached = _sftpByProfile[profile.id];
    if (cached != null) {
      try {
        await cached.absolute('.');
        return cached;
      } on Object {
        _sftpByProfile.remove(profile.id);
      }
    }

    final client = await clientForStorage(profile);
    final sftp = await client.sftp();
    _sftpByProfile[profile.id] = sftp;
    return sftp;
  }

  void disconnectProfile(String profileId) {
    _evictProfile(profileId, closePooled: true);
  }

  void _evictProfile(String profileId, {required bool closePooled}) {
    _sftpByProfile.remove(profileId);
    final cached = _pool.remove(profileId);
    final wasLive = cached != null && cached.readyCompleted;
    if (closePooled && cached != null && !cached.client.isClosed) {
      cached.client.close();
    }
    if (wasLive) {
      _notifyPoolChange(profileId);
    }
  }

  void _attachTransportLifecycle(String profileId, SSHClient client) {
    if (!_watchedClients.add(client)) return;
    client.done.then(
      (_) => _handleProfileTransportClosed(
        profileId,
        StateError('SSH transport closed'),
        StackTrace.empty,
      ),
      onError: (Object error) => _handleProfileTransportClosed(
        profileId,
        error,
        StackTrace.current,
      ),
    );
  }

  void _handleProfileTransportClosed(
    String profileId,
    Object error,
    StackTrace stackTrace,
  ) {
    _evictProfile(profileId, closePooled: false);
    _events.onTransportClosed?.call(profileId, error, stackTrace);
  }

  void _handleKeepAliveFailed(
    String profileId,
    Object error,
    StackTrace stackTrace,
  ) {
    _events.onKeepAliveFailed?.call(profileId, error, stackTrace);
  }

  void disconnectAll() {
    _sftpByProfile.clear();
    for (final cached in _pool.values) {
      if (!cached.client.isClosed) {
        cached.client.close();
      }
    }
    _pool.clear();
  }

  /// One-off connectivity check using form credentials without persisting the
  /// profile or touching the shared connection pool.
  Future<void> testConnection(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    final store = _CredentialOverrideStore(
      base: _credentialStore,
      profileId: profile.id,
      password: password,
      privateKey: privateKey,
      privateKeyPassphrase: privateKeyPassphrase,
    );
    final ephemeral = SshClientFactory(
      credentialStore: store,
      knownHostRepository: _knownHostRepository,
      onHostKeyPrompt: _onHostKeyPrompt,
      onHostKeyPersist: _onHostKeyPersist,
      connector: _connector,
    );
    final client = await ephemeral.createClient(profile);
    try {
      await client.authenticated;
    } finally {
      if (!client.isClosed) {
        client.close();
      }
    }
  }

  /// Canonical host-key identity for storage/UI.
  ///
  /// TerminalStudio dartssh2 (≥2.18) passes UTF-8 bytes of an OpenSSH-style
  /// `SHA256:<base64>` fingerprint. Older forks passed a raw digest; those
  /// remain hex-colon encoded for compatibility.
  static String fingerprintIdentity(Uint8List fingerprint) {
    final asText = utf8.decode(fingerprint, allowMalformed: true);
    if (asText.startsWith('SHA256:')) return asText;
    return fingerprintToHex(fingerprint);
  }

  static String fingerprintToHex(Uint8List fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(fingerprint[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String fingerprintToBase64(Uint8List fingerprint) {
    final identity = fingerprintIdentity(fingerprint);
    if (identity.startsWith('SHA256:')) {
      return identity.substring('SHA256:'.length);
    }
    return base64.encode(fingerprint);
  }

  /// Opens a fresh, caller-owned SSH connection for one member session plane.
  Future<SSHClient> createMemberClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) => _connectClient(profile, timeout: timeout);

  Future<SSHClient> createClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) => _connectClient(profile, timeout: timeout);

  Future<SSHClient> _connectClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final client = _connector != null
        ? await _connector!(profile, timeout: timeout)
        : await _openClient(profile, timeout: timeout);
    _attachTransportLifecycle(profile.id, client);
    return client;
  }

  Future<SSHClient> _openClient(
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
          onKeepAliveFailed: (error, stackTrace) =>
              _handleKeepAliveFailed(profile.id, error, stackTrace),
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
          onKeepAliveFailed: (error, stackTrace) =>
              _handleKeepAliveFailed(profile.id, error, stackTrace),
        );
    }
  }
}

class _CredentialOverrideStore implements SshCredentialStore {
  _CredentialOverrideStore({
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
  Future<String?> loadPassword(String id) async {
    if (id == profileId && _hasOverride(password)) return password;
    return _base.loadPassword(id);
  }

  @override
  Future<String?> loadPrivateKey(String id) async {
    if (id == profileId && _hasOverride(privateKey)) return privateKey;
    return _base.loadPrivateKey(id);
  }

  @override
  Future<String?> loadPrivateKeyPassphrase(String id) async {
    if (id == profileId && _hasOverride(privateKeyPassphrase)) {
      return privateKeyPassphrase;
    }
    return _base.loadPrivateKeyPassphrase(id);
  }

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
  Future<void> deleteAll(String profileId) => _base.deleteAll(profileId);
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
    final fingerprintHex = SshClientFactory.fingerprintIdentity(fingerprint);
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
