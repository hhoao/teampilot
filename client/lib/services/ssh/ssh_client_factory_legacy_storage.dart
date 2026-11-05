part of 'ssh_client_factory.dart';

/// Raw dartssh2 compatibility surface for tests that inject a direct connector.
/// Production callers must use [SshClientFactory.storageFor].
extension SshClientFactoryLegacyStorage on SshClientFactory {
  Future<SSHRunResult> _runOnLegacyStorage(
    SshProfile profile,
    String command, {
    required Duration timeout,
    required bool stderr,
  }) async {
    final client = await clientForStorage(profile);
    try {
      return await SshStorageIo.awaitOrThrow(
        client.runWithResult(command, stderr: stderr),
        timeout: timeout,
        operation: 'storage exec',
      );
    } on TimeoutException {
      _evictLegacyProfile(
        profile.id,
        closePooled: true,
        reason: SshTransportCloseReason.transportError,
      );
      rethrow;
    }
  }

  Future<SSHClient> clientForStorage(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
    bool probeCached = true,
  }) async {
    if (_connector == null) {
      throw StateError(
        'Raw SSH storage clients are test-only; use storageFor instead',
      );
    }
    final cached = _legacyPool[profile.id];
    if (cached != null) {
      if (cached.client.isClosed) {
        _legacyPool.remove(profile.id);
        _legacySftpByProfile.remove(profile.id);
      } else if (cached.hostIdentifier == profile.hostIdentifier) {
        await cached.ready;
        final inFlight = _inFlight[profile.id] ?? 0;
        final skipProbe = !probeCached || inFlight > 0;
        if (skipProbe || await _probeStorageClient(cached.client)) {
          return cached.client;
        }
        if ((_inFlight[profile.id] ?? 0) > 0) {
          return cached.client;
        }
        _evictLegacyProfile(
          profile.id,
          closePooled: true,
          reason: SshTransportCloseReason.transportError,
        );
      } else {
        _evictLegacyProfile(
          profile.id,
          closePooled: true,
          reason: SshTransportCloseReason.hostIdentityChanged,
        );
      }
    }

    final client = await _connectClient(
      profile,
      plane: SshTransportPlane.storage,
      timeout: timeout,
    );
    final ready = client.authenticated;
    final pooled = _PooledConnection(
      client: client,
      hostIdentifier: profile.hostIdentifier,
      ready: ready,
    );
    _legacyPool[profile.id] = pooled;
    try {
      await ready;
      pooled.readyCompleted = true;
      _notifyPoolChange(profile.id);
    } on Object {
      _evictLegacyProfile(
        profile.id,
        closePooled: true,
        reason: SshTransportCloseReason.authFailed,
      );
      rethrow;
    }
    return client;
  }

  Future<bool> _probeStorageClient(SSHClient client) async {
    if (client.isClosed) return false;
    try {
      await SshStorageIo.awaitOrThrow(
        client.ping(),
        timeout: SshStorageIo.probeTimeout,
        operation: 'storage keepalive probe',
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<SftpClient> sftpFor(SshProfile profile) async {
    if (_connector == null) {
      throw StateError(
        'Raw SFTP clients are test-only; use storageFor instead',
      );
    }
    final cached = _legacySftpByProfile[profile.id];
    if (cached != null) {
      try {
        await SshStorageIo.awaitOrThrow(
          cached.absolute('.'),
          timeout: SshStorageIo.probeTimeout,
          operation: 'sftp liveness probe',
        );
        return cached;
      } on Object {
        _legacySftpByProfile.remove(profile.id);
      }
    }

    return _openSftp(profile);
  }

  Future<SftpClient> _openSftp(SshProfile profile) async {
    final client = await clientForStorage(profile);
    try {
      final sftp = await SshStorageIo.awaitOrThrow(
        client.sftp(),
        timeout: SshStorageIo.ioTimeout,
        operation: 'sftp open',
      );
      _legacySftpByProfile[profile.id] = sftp;
      return sftp;
    } on Object {
      _evictLegacyProfile(
        profile.id,
        closePooled: true,
        reason: SshTransportCloseReason.transportError,
      );
      rethrow;
    }
  }
}
