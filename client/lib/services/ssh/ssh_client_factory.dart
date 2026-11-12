import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../../utils/logging/logger.dart';
import '../host/process_run_handle.dart';
import '../chat/team_bus/remote/reverse_tunnel.dart';
import 'ssh_connection_events.dart';
import 'ssh_connection_failure.dart';
import 'ssh_connection_gate.dart';
import 'ssh_client_factory_support.dart';
import 'ssh_credentials_resolver.dart';
import 'ssh_forward_channel.dart';
import 'ssh_storage_io.dart';
import 'ssh_transport_close.dart';
import 'worker/ssh_worker_auth_bridge.dart';
import 'worker/ssh_worker_member_session.dart';
import 'worker/ssh_worker_forward_proxy.dart';
import 'worker/ssh_profile_worker_manager.dart';
import 'worker/ssh_worker_protocol.dart';
import 'worker/ssh_worker_storage_client.dart';
import 'worker/ssh_worker_storage_types.dart';

export 'worker/ssh_worker_auth_bridge.dart'
    show HostKeyPromptInfo, SshHostKeyTrustPolicy;
export 'ssh_forward_channel.dart' show SshForwardByteChannel;

part 'ssh_client_factory_storage.dart';
part 'ssh_client_factory_narrow_operations.dart';
part 'ssh_client_factory_legacy_storage.dart';

typedef SshClientConnector =
    Future<SSHClient> Function(SshProfile profile, {Duration timeout});

typedef SshMemberReverseTunnelFactory =
    ReverseTunnel Function(SshProfile profile, {required String bindHost});

/// Returns the actual socket target for [profile], or null to use the
/// stored host/port. Relay-paired profiles route through this while a
/// loopback tunnel lives.
typedef SshDialTargetResolver =
    Future<({InternetAddress address, int port})?> Function(SshProfile profile);

class _ClientLifecycle {
  _ClientLifecycle({required this.profileId, required this.plane});

  final String profileId;
  final SshTransportPlane plane;
  SshTransportCloseReason? pendingLocalCloseReason;
}

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

class SshClientFactory {
  SshClientFactory({
    required SshCredentialStore credentialStore,
    required SshKnownHostRepository knownHostRepository,
    SshConnectionEvents? events,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
    SshClientConnector? connector,
    SshMemberReverseTunnelFactory? memberReverseTunnelFactory,
    SshDialTargetResolver? dialTargetResolver,
    VaultCredentialReader? vaultCredentials,
    SshVaultEntryIdResolver? vaultEntryIdFor,
    SshWorkerAuthBridge? workerAuthBridge,
    SshProfileWorkerManager? workerManager,
    SshConnectionGate? connectionGate,
    int maxConcurrentHandshakes = 3,
    this.drainGracePeriod = const Duration(seconds: 5),
    this.storageProbeInterval = const Duration(seconds: 15),
  }) : _credentialStore = credentialStore,
       _knownHostRepository = knownHostRepository,
       _events = events ?? SshConnectionEvents(),
       _onHostKeyPrompt = onHostKeyPrompt,
       _onHostKeyPersist = onHostKeyPersist,
       _dialTargetResolver = dialTargetResolver,
       _workerAuthBridge =
           workerAuthBridge ??
           SshWorkerAuthBridge(
             credentialStore: credentialStore,
             knownHostRepository: knownHostRepository,
             onHostKeyPrompt: onHostKeyPrompt,
             onHostKeyPersist: onHostKeyPersist,
             dialTargetResolver: dialTargetResolver,
             vault: vaultCredentials,
             vaultEntryIdFor: vaultEntryIdFor,
           ),
       _connector = connector,
       _memberReverseTunnelFactory = memberReverseTunnelFactory,
       connectionGate = connectionGate ?? SshConnectionGate(),
       _handshakeGate = SshHandshakeGate(maxConcurrentHandshakes) {
    final resolvedWorkerManager =
        workerManager ??
        SshProfileWorkerManager(authChallengeHandlerFor: workerAuthHandlerFor);
    this.workerManager = resolvedWorkerManager;
    _workerEventsSubscription = resolvedWorkerManager.events.listen(
      _onWorkerManagerEvent,
    );
    _workerStoragePool = _SshWorkerStoragePool(
      manager: resolvedWorkerManager,
      probeInterval: storageProbeInterval,
      resolveDialTarget: resolveWorkerDialTarget,
      waitForDrain: (profileId) =>
          _waitForTrackedOperations(profileId, drainGracePeriod),
      isBusy: (profileId) => (_inFlight[profileId] ?? 0) > 0,
      onPoolChanged: _notifyPoolChange,
      onTransportClosed: (profileId, reason, stackTrace) {
        _events.onTransportClosed?.call(
          profileId,
          SshTransportClosed(reason: reason, plane: SshTransportPlane.storage),
          stackTrace,
        );
      },
    );
  }

  /// Maximum time an evicted storage connection remains available to
  /// operations that already borrowed it.
  final Duration drainGracePeriod;

  /// How often a cached storage lease is probed before reuse. Overridable in
  /// tests so probe behavior can be exercised without waiting out the window.
  final Duration storageProbeInterval;

  /// Per-profile dial gate shared by every plane. Normal callers must go
  /// through it; only [SshProfileConnectionCoordinator] may bypass it.
  final SshConnectionGate connectionGate;

  final SshCredentialStore _credentialStore;
  final SshKnownHostRepository _knownHostRepository;
  final SshConnectionEvents _events;
  final Future<bool> Function(HostKeyPromptInfo)? _onHostKeyPrompt;
  final void Function(String storageKey, String fingerprintHex)?
  _onHostKeyPersist;
  final SshDialTargetResolver? _dialTargetResolver;
  final SshWorkerAuthBridge _workerAuthBridge;
  final SshClientConnector? _connector;
  final SshMemberReverseTunnelFactory? _memberReverseTunnelFactory;
  final SshHandshakeGate _handshakeGate;
  // Raw dartssh2 storage access remains only as a compatibility seam for
  // injected connector tests. Production storage is held by worker leases.
  final Map<String, _PooledConnection> _legacyPool = {};
  final Map<String, SftpClient> _legacySftpByProfile = {};
  final Map<String, int> _inFlight = {};
  final Set<SSHClient> _watchedClients = {};
  final Map<SSHClient, _ClientLifecycle> _clientLifecycle = {};
  late final _SshWorkerStoragePool _workerStoragePool;
  late final SshProfileWorkerManager workerManager;
  late final StreamSubscription<SshProfileWorkerManagerEvent>
  _workerEventsSubscription;
  final _poolChanges = StreamController<String>.broadcast();
  Future<void>? _closeFuture;

  /// Creates the UI-isolate auth handler for one profile worker generation.
  SshWorkerAuthChallengeHandler workerAuthHandlerFor(SshProfile profile) {
    return _workerAuthBridge.handlerFor(profile);
  }

  /// Snapshots the current relay/direct target for a new worker generation.
  ///
  /// Callers must invoke this immediately before connecting that generation so
  /// a recreated relay tunnel is never inherited from an older worker.
  Future<SshWorkerDialTarget> resolveWorkerDialTarget(SshProfile profile) {
    return _workerAuthBridge.dialTargetFor(profile);
  }

  bool hasLiveStorageClient(String profileId) {
    if (_workerStoragePool.hasLiveClient(profileId)) return true;
    final cached = _legacyPool[profileId];
    return cached != null && !cached.client.isClosed && cached.readyCompleted;
  }

  Stream<String> get storagePoolChanges => _poolChanges.stream;

  void _notifyPoolChange(String profileId) {
    if (!_poolChanges.isClosed) _poolChanges.add(profileId);
  }

  void _onWorkerManagerEvent(SshProfileWorkerManagerEvent envelope) {
    if (!workerManager.isCurrentGeneration(
      envelope.profileId,
      envelope.generation,
    )) {
      return;
    }
    final event = envelope.event;
    if (event.kind != SshWorkerEventKind.transportClose ||
        event.plane == null ||
        event.reason == null) {
      return;
    }
    _events.onTransportClosed?.call(
      envelope.profileId,
      SshTransportClosed(reason: event.reason!, plane: event.plane!),
      StackTrace.current,
    );
  }

  /// Pooled worker storage-plane client for [profile] (SFTP / file I/O only).
  ///
  /// Interactive session work (PTY, reverse bus tunnels, exec probes) must use
  /// [createMemberClient] via [SshMemberSession.open] instead.
  ///
  /// Reuses a pooled client only after a short keepalive probe so half-dead
  /// sockets (FIN not yet observed) are rebuilt instead of hanging callers.
  Future<SshWorkerStorageClient> storageFor(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
    bool probeCached = true,
    bool allowDialWhenDown = false,
  }) async {
    if (allowDialWhenDown) {
      connectionGate.allowNextDial(profile.id);
    }
    // Always enforce suspension: `allowNextDial` deliberately does not clear a
    // user/permanent stop, so this second check is what keeps a bypass from
    // overriding it.
    connectionGate.beforeIo(profile.id);
    connectionGate.markConnecting(profile.id);
    try {
      final client = await _workerStoragePool.clientFor(
        profile,
        timeout: timeout,
        probeCached: probeCached,
      );
      connectionGate.markUp(profile.id);
      return client;
    } on Object catch (error, stackTrace) {
      if (isSshTransportConnectionFailure(error)) {
        connectionGate.markDown(profile.id);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Opens a primitive-only member transport backed by the profile worker.
  ///
  /// An injected [connector] remains a direct adapter for legacy pure tests;
  /// it never changes the production worker path.
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    connectionGate.beforeIo(profile.id);
    if (_connector != null) {
      final client = await createMemberClient(profile, timeout: timeout);
      try {
        await client.authenticated;
        connectionGate.markUp(profile.id);
      } on Object catch (error, stackTrace) {
        if (isSshTransportConnectionFailure(error)) {
          connectionGate.markDown(profile.id);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return _GatedMemberTransport(
        gate: connectionGate,
        profileId: profile.id,
        inner: SshWorkerDirectMemberTransport(
          client: client,
          closeTransport: () async {
            prepareClientClose(
              client,
              reason: SshTransportCloseReason.memberSessionClosed,
            );
            await _disconnectQuietly(client);
          },
        ),
      );
    }
    final lease = await workerManager.acquire(profile);
    try {
      final target = await resolveWorkerDialTarget(profile);
      return _GatedMemberTransport(
        gate: connectionGate,
        profileId: profile.id,
        inner: SshWorkerLeaseMemberTransport(lease: lease, target: target),
      );
    } on Object {
      await lease.release();
      rethrow;
    }
  }

  /// Ensures the profile worker storage plane is connected without exposing
  /// its facade to callers that only need a readiness check.
  ///
  /// [allowDialWhenDown] is reserved for the single reconnect driver; it lets
  /// the coordinator dial while the gate is down instead of failing fast.
  Future<void> ensureStorageConnected(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
    bool probeCached = true,
    bool allowDialWhenDown = false,
  }) async {
    if (_connector != null) {
      await clientForStorage(
        profile,
        timeout: timeout,
        probeCached: probeCached,
      );
      return;
    }
    await storageFor(
      profile,
      timeout: timeout,
      probeCached: probeCached,
      allowDialWhenDown: allowDialWhenDown,
    );
  }

  /// Runs [command] on the storage-plane client with an I/O timeout.
  ///
  /// On timeout the pooled worker is evicted so the next caller rebuilds.
  Future<SSHRunResult> runOnStorage(
    SshProfile profile,
    String command, {
    Duration timeout = SshStorageIo.ioTimeout,
    bool stderr = true,
  }) => _tracked(profile.id, () async {
    if (_connector != null) {
      return _runOnLegacyStorage(
        profile,
        command,
        timeout: timeout,
        stderr: stderr,
      );
    }

    try {
      final result = await (await storageFor(
        profile,
        timeout: timeout,
      )).run(command, stderr: stderr, timeout: timeout);
      return _toSshRunResult(result);
    } on SshWorkerTransportException catch (error) {
      if (error.code != 'transport_timeout') rethrow;
      _workerStoragePool.disconnectStorage(
        profile.id,
        reason: SshTransportCloseReason.transportError,
      );
      throw TimeoutException('storage exec', timeout);
    }
  });

  /// Rejects exec argv longer than this so large payloads go on stdin.
  static const maxExecCommandBytes = 1024;

  /// Runs [command] on the storage plane, writing [stdin] then closing it.
  Future<SSHRunResult> runOnStorageWithStdin(
    SshProfile profile,
    String command, {
    required List<int> stdin,
    Duration timeout = SshStorageIo.provisionPhaseTimeout,
    bool stderr = true,
  }) {
    if (utf8.encode(command).length > maxExecCommandBytes) {
      throw StateError(
        'storage exec command exceeds $maxExecCommandBytes bytes',
      );
    }
    return _tracked(profile.id, () async {
      if (_connector != null) {
        final client = await clientForStorage(profile);
        try {
          return await SshStorageIo.awaitOrThrow(
            client.runWithResult(command, stderr: stderr, stdin: stdin),
            timeout: timeout,
            operation: 'storage exec stdin',
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
      try {
        final result = await (await storageFor(profile, timeout: timeout)).run(
          command,
          stderr: stderr,
          stdin: Uint8List.fromList(stdin),
          timeout: timeout,
        );
        return _toSshRunResult(result);
      } on SshWorkerTransportException catch (error) {
        if (error.code != 'transport_timeout') rethrow;
        _workerStoragePool.disconnectStorage(
          profile.id,
          reason: SshTransportCloseReason.transportError,
        );
        throw TimeoutException('storage exec stdin', timeout);
      }
    });
  }

  SSHRunResult _toSshRunResult(SshWorkerRunResult result) {
    // The worker DTO intentionally keeps stdout and stderr separate and cannot
    // represent dartssh2's arrival-order interleaving. Preserve both captures;
    // compatibility `output` is therefore defined as stdout followed by stderr.
    final output =
        (BytesBuilder(copy: false)
              ..add(result.stdout)
              ..add(result.stderr))
            .takeBytes();
    final signal = result.signalName;
    return SSHRunResult(
      output: output,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      exitSignal: signal == null
          ? null
          : SSHSessionExitSignal(
              signalName: signal,
              coreDumped: false,
              errorMessage: '',
              languageTag: '',
            ),
    );
  }

  /// Tracks a storage operation so an evicted client is not closed underneath
  /// an SFTP channel or storage exec that is already using it.
  Future<T> runTracked<T>(String profileId, Future<T> Function() operation) =>
      _tracked(profileId, operation);

  Future<T> _tracked<T>(
    String profileId,
    Future<T> Function() operation,
  ) async {
    _inFlight[profileId] = (_inFlight[profileId] ?? 0) + 1;
    try {
      return await operation();
    } finally {
      final remaining = (_inFlight[profileId] ?? 1) - 1;
      if (remaining <= 0) {
        _inFlight.remove(profileId);
      } else {
        _inFlight[profileId] = remaining;
      }
    }
  }

  void prepareClientClose(
    SSHClient client, {
    required SshTransportCloseReason reason,
  }) {
    _clientLifecycle[client]?.pendingLocalCloseReason = reason;
  }

  void disconnectStorage(
    String profileId, {
    SshTransportCloseReason reason = SshTransportCloseReason.transportError,
  }) {
    _workerStoragePool.disconnectStorage(profileId, reason: reason);
  }

  void disconnectProfile(
    String profileId, {
    SshTransportCloseReason reason = SshTransportCloseReason.userDisconnect,
  }) {
    if (reason == SshTransportCloseReason.userDisconnect) {
      connectionGate.suspend(profileId);
    }
    _workerStoragePool.disconnectProfile(profileId, reason: reason);
    _evictLegacyProfile(profileId, closePooled: true, reason: reason);
  }

  void _evictLegacyProfile(
    String profileId, {
    required bool closePooled,
    SshTransportCloseReason? reason,
  }) {
    _legacySftpByProfile.remove(profileId);
    final cached = _legacyPool.remove(profileId);
    final wasLive = cached != null && cached.readyCompleted;
    if (closePooled && cached != null && !cached.client.isClosed) {
      final lifecycle = _clientLifecycle[cached.client];
      if (lifecycle != null && reason != null) {
        lifecycle.pendingLocalCloseReason = reason;
      }
      final inFlight = _inFlight[profileId] ?? 0;
      if (inFlight > 0) {
        appLogger.i(
          '[ssh] deferring close profile=$profileId inFlight=$inFlight',
        );
        unawaited(
          _closeWhenDrained(profileId, cached.client, drainGracePeriod),
        );
      } else {
        unawaited(_disconnectQuietly(cached.client));
      }
    }
    if (wasLive) {
      _notifyPoolChange(profileId);
    }
  }

  static const _drainPollInterval = Duration(milliseconds: 50);

  Future<void> _closeWhenDrained(
    String profileId,
    SSHClient client,
    Duration timeout,
  ) async {
    await _waitForTrackedOperations(profileId, timeout);
    if (!client.isClosed) await _disconnectQuietly(client);
  }

  Future<void> _waitForTrackedOperations(
    String profileId,
    Duration timeout,
  ) async {
    var pollsLeft = timeout.inMilliseconds ~/ _drainPollInterval.inMilliseconds;
    while ((_inFlight[profileId] ?? 0) > 0 && pollsLeft > 0) {
      await Future<void>.delayed(_drainPollInterval);
      pollsLeft--;
    }
  }

  Future<void> _disconnectQuietly(SSHClient client) async {
    try {
      await client.disconnect();
    } on Object {
      // Channel teardown can race with dartssh2's close propagation. The
      // owning operation already receives the transport error if applicable.
    }
  }

  void _attachTransportLifecycle(
    String profileId,
    SSHClient client,
    SshTransportPlane plane,
  ) {
    if (!_watchedClients.add(client)) return;
    _clientLifecycle[client] = _ClientLifecycle(
      profileId: profileId,
      plane: plane,
    );
    client.done.then(
      (_) => _onClientDone(client, null, StackTrace.empty),
      onError: (Object error) =>
          _onClientDone(client, error, StackTrace.current),
    );
  }

  void _onClientDone(SSHClient client, Object? error, StackTrace stackTrace) {
    final lifecycle = _clientLifecycle.remove(client);
    _watchedClients.remove(client);
    if (lifecycle == null) return;

    final reason =
        lifecycle.pendingLocalCloseReason ??
        (error != null
            ? SshTransportCloseReason.transportError
            : SshTransportCloseReason.remotePeerClosed);

    if (lifecycle.plane == SshTransportPlane.storage) {
      final cached = _legacyPool[lifecycle.profileId];
      if (cached != null && identical(cached.client, client)) {
        _evictLegacyProfile(lifecycle.profileId, closePooled: false);
      }
    }

    _events.onTransportClosed?.call(
      lifecycle.profileId,
      SshTransportClosed(reason: reason, plane: lifecycle.plane, cause: error),
      stackTrace,
    );
  }

  void disconnectAll({
    SshTransportCloseReason reason = SshTransportCloseReason.disconnectAll,
  }) {
    for (final profileId in _legacyPool.keys.toList()) {
      _evictLegacyProfile(profileId, closePooled: true, reason: reason);
    }
    _workerStoragePool.disconnectAll(reason: reason);
    _legacySftpByProfile.clear();
  }

  /// Stops factory listeners before closing every worker generation.
  ///
  /// App shutdown invokes this only after terminal, member, and storage
  /// producers have stopped issuing requests.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    disconnectAll();
    connectionGate.dispose();
    await _workerEventsSubscription.cancel();
    await workerManager.close();
    await _poolChanges.close();
  }

  /// One-off connectivity check using form credentials without persisting the
  /// profile or touching the shared connection pool.
  Future<void> testConnection(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    final store = SshCredentialOverrideStore(
      base: _credentialStore,
      profileId: profile.id,
      password: password,
      privateKey: privateKey,
      privateKeyPassphrase: privateKeyPassphrase,
    );
    final bridge = SshWorkerAuthBridge(
      credentialStore: store,
      knownHostRepository: _knownHostRepository,
      onHostKeyPrompt: _onHostKeyPrompt,
      onHostKeyPersist: _onHostKeyPersist,
      dialTargetResolver: _dialTargetResolver,
    );
    final ephemeral = SshClientFactory(
      credentialStore: store,
      knownHostRepository: _knownHostRepository,
      onHostKeyPrompt: _onHostKeyPrompt,
      onHostKeyPersist: _onHostKeyPersist,
      connector: _connector,
      dialTargetResolver: _dialTargetResolver,
      workerAuthBridge: bridge,
      workerManager: workerManager.detached(
        authChallengeHandlerFor: bridge.handlerFor,
      ),
    );
    if (_connector == null) {
      try {
        await ephemeral.ensureStorageConnected(profile);
      } finally {
        await ephemeral.close();
      }
      return;
    }

    final client = await ephemeral.createClient(profile);
    try {
      await client.authenticated;
    } finally {
      if (!client.isClosed) {
        // Not awaited: teardown must not block the caller — the transport's
        // socket close can outlive it.
        unawaited(client.disconnect());
      }
      await ephemeral.close();
    }
  }

  /// Canonical host-key identity for storage/UI.
  ///
  /// TerminalStudio dartssh2 (≥2.18) passes UTF-8 bytes of an OpenSSH-style
  /// `SHA256:<base64>` fingerprint. Older forks passed a raw digest; those
  /// remain hex-colon encoded for compatibility.
  static String fingerprintIdentity(Uint8List fingerprint) {
    return SshWorkerAuthBridge.fingerprintIdentity(fingerprint);
  }

  static String fingerprintToHex(Uint8List fingerprint) =>
      SshWorkerAuthBridge.fingerprintToHex(fingerprint);

  static String fingerprintToBase64(Uint8List fingerprint) =>
      SshWorkerAuthBridge.fingerprintToBase64(fingerprint);

  /// Direct-client compatibility adapter for connector-injected tests.
  ///
  /// Production one-shot work must use a profile-worker storage or member
  /// facade so a dartssh2 client never enters the UI isolate.
  Future<SSHClient> createEphemeralClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final connector = _connector;
    if (connector == null) {
      throw StateError(
        'Raw SSH clients are test-only; inject a connector or use worker APIs',
      );
    }
    final key = profile.hostIdentifier;
    await _handshakeGate.acquire(key);
    try {
      final client = await connector(profile, timeout: timeout);
      _releaseGateWhenSettled(key, client);
      return client;
    } on Object {
      _handshakeGate.release(key);
      rethrow;
    }
  }

  /// Direct-client compatibility adapter for connector-injected tests.
  ///
  /// Production member work must use [openMemberTransport].
  Future<SSHClient> createMemberClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) => _connectClient(
    profile,
    plane: SshTransportPlane.member,
    timeout: timeout,
  );

  /// Legacy alias retained for connector-injected tests.
  Future<SSHClient> createClient(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) => _connectClient(
    profile,
    plane: SshTransportPlane.member,
    timeout: timeout,
  );

  Future<SSHClient> _connectClient(
    SshProfile profile, {
    required SshTransportPlane plane,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final connector = _connector;
    if (connector == null) {
      throw StateError(
        'Raw SSH clients are test-only; inject a connector or use worker APIs',
      );
    }
    final key = profile.hostIdentifier;
    await _handshakeGate.acquire(key);
    final SSHClient client;
    try {
      client = await connector(profile, timeout: timeout);
    } on Object {
      _handshakeGate.release(key);
      rethrow;
    }
    _releaseGateWhenSettled(key, client);
    _attachTransportLifecycle(profile.id, client, plane);
    return client;
  }

  /// A handshake slot is held until the connection authenticates, fails, or
  /// closes — every unauthenticated connection counts against the server's
  /// `MaxStartups` budget, not just the ones still dialing.
  void _releaseGateWhenSettled(String key, SSHClient client) {
    client.authenticated
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() => _handshakeGate.release(key));
  }
}

/// Wraps a member transport so the shared connection gate observes the actual
/// dial (`open`), not just the lease acquisition.
final class _GatedMemberTransport implements SshWorkerMemberTransport {
  _GatedMemberTransport({
    required this.gate,
    required this.profileId,
    required this.inner,
  });

  final SshConnectionGate gate;
  final String profileId;
  final SshWorkerMemberTransport inner;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    gate.beforeIo(profileId);
    gate.markConnecting(profileId);
    try {
      await inner.open(profile, timeout: timeout);
      gate.markUp(profileId);
    } on Object catch (error, stackTrace) {
      if (isSshTransportConnectionFailure(error)) {
        gate.markDown(profileId);
      } else {
        gate.markUp(profileId);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) =>
      inner.run(command, stderr: stderr);

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      inner.startProcess(command);

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => inner.openPty(
    command: command,
    columns: columns,
    rows: rows,
    environment: environment,
  );

  @override
  Future<void> close() => inner.close();
}
