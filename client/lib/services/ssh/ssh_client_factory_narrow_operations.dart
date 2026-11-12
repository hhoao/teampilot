part of 'ssh_client_factory.dart';

/// App-owned process and forwarding surfaces backed by the profile worker.
extension SshClientFactoryNarrowOperations on SshClientFactory {
  Future<ProcessRunHandle> startProcess(
    SshProfile profile,
    String command, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final transport = await openMemberTransport(profile, timeout: timeout);
    try {
      final session = await SshWorkerMemberSession.open(
        profile: profile,
        transport: transport,
        timeout: timeout,
      );
      final process = await session.startProcess(command);
      return _WorkerMemberProcessRunHandle(session, process);
    } on Object {
      await transport.close();
      rethrow;
    }
  }

  /// Narrow reverse-tunnel seam backed by the profile worker in production.
  ReverseTunnel newMemberReverseTunnel(
    SshProfile profile, {
    String bindHost = '127.0.0.1',
  }) {
    final injected = _memberReverseTunnelFactory;
    if (injected != null) {
      return injected(profile, bindHost: bindHost);
    }
    if (_connector != null) {
      return _FactoryOwnedReverseTunnel(
        openClient: () => createMemberClient(profile),
        bindHost: bindHost,
        onClientClosing: (client) => prepareClientClose(
          client,
          reason: SshTransportCloseReason.memberSessionClosed,
        ),
        disconnectClient: _disconnectQuietly,
      );
    }
    return _WorkerOwnedReverseTunnel(
      openSession: () => _openWorkerForwardSession(profile),
      bindHost: bindHost,
    );
  }

  Future<SshForwardByteChannel> openForwardChannel(
    SshProfile profile,
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ioGuard(profile.id);
    if (_connector != null) {
      final client = await createMemberClient(profile, timeout: timeout);
      try {
        final channel = await client.forwardLocal(host, port);
        return DartSshForwardByteChannel(
          client: client,
          channel: channel,
          onClosing: () => prepareClientClose(
            client,
            reason: SshTransportCloseReason.memberSessionClosed,
          ),
        );
      } on Object catch (error, stackTrace) {
        await _disconnectQuietly(client);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    final session = await _openWorkerForwardSession(profile, timeout: timeout);
    try {
      return await session.openLocal(host, port);
    } on Object catch (error, stackTrace) {
      await session.close();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<SshWorkerForwardSession> _openWorkerForwardSession(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ioGuard(profile.id);
    final lease = await workerManager.acquire(profile);
    try {
      final target = await resolveWorkerDialTarget(profile);
      return SshWorkerForwardSession(
        profile: profile,
        lease: lease,
        target: target,
        timeout: timeout,
      );
    } on Object {
      await lease.release();
      rethrow;
    }
  }
}

final class _WorkerOwnedReverseTunnel implements ReverseTunnel {
  _WorkerOwnedReverseTunnel({
    required this.openSession,
    required this.bindHost,
  });

  final Future<SshWorkerForwardSession> Function() openSession;
  final String bindHost;
  ReverseTunnel? _tunnel;
  SshWorkerForwardSession? _session;
  Future<void>? _closeFuture;
  var _closed = false;

  @override
  Stream<TunnelChannel> get channels =>
      _tunnel?.channels ?? const Stream<TunnelChannel>.empty();

  @override
  Future<int> open() async {
    if (_closed) throw StateError('Reverse tunnel is closed');
    if (_tunnel != null) throw StateError('Reverse tunnel is already open');
    final session = await openSession();
    _session = session;
    if (_closed) {
      await session.close();
      throw StateError('Reverse tunnel is closed');
    }
    try {
      final tunnel = await session.openRemote(bindHost);
      if (_closed) {
        await session.close();
        throw StateError('Reverse tunnel is closed');
      }
      _tunnel = tunnel;
      return await tunnel.open();
    } on Object {
      await session.close();
      rethrow;
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _tunnel?.close();
    await _session?.close();
  }
}

final class _WorkerMemberProcessRunHandle implements ProcessRunHandle {
  _WorkerMemberProcessRunHandle(this._session, this._process) {
    unawaited(_run());
  }

  final SshWorkerMemberSession _session;
  final SshWorkerExecChannel _process;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  var _killRequested = false;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  void kill() {
    if (_killRequested) return;
    _killRequested = true;
    _process.kill();
  }

  Future<void> _run() async {
    try {
      final stdoutSubscription = _process.stdout.listen(_stdout.add);
      final stderrSubscription = _process.stderr.listen(_stderr.add);
      final exitCode = await _process.done;
      await Future.wait([
        stdoutSubscription.cancel(),
        stderrSubscription.cancel(),
      ]);
      unawaited(_stdout.close());
      unawaited(_stderr.close());
      await _closeSessionQuietly();
      if (!_exitCode.isCompleted) _exitCode.complete(exitCode);
    } on Object catch (error, stackTrace) {
      _stdout.addError(error, stackTrace);
      _stderr.addError(error, stackTrace);
      _process.close();
      unawaited(_stdout.close());
      unawaited(_stderr.close());
      await _closeSessionQuietly();
      if (!_exitCode.isCompleted) _exitCode.completeError(error, stackTrace);
    }
  }

  Future<void> _closeSessionQuietly() async {
    try {
      await _session.close();
    } on Object {
      // The process result is authoritative; member cleanup is best effort.
    }
  }
}

final class _FactoryOwnedReverseTunnel implements ReverseTunnel {
  _FactoryOwnedReverseTunnel({
    required this.openClient,
    required this.bindHost,
    required this.onClientClosing,
    required this.disconnectClient,
  });

  final Future<SSHClient> Function() openClient;
  final String bindHost;
  final void Function(SSHClient client) onClientClosing;
  final Future<void> Function(SSHClient client) disconnectClient;
  SSHClient? _client;
  DartSshReverseTunnel? _tunnel;
  Future<void>? _closeFuture;
  var _closed = false;

  @override
  Stream<TunnelChannel> get channels =>
      _tunnel?.channels ?? const Stream<TunnelChannel>.empty();

  @override
  Future<int> open() async {
    if (_closed) throw StateError('Reverse tunnel is closed');
    if (_tunnel != null) throw StateError('Reverse tunnel is already open');
    final client = await openClient();
    final tunnel = DartSshReverseTunnel(client, bindHost: bindHost);
    _client = client;
    _tunnel = tunnel;
    try {
      return await tunnel.open();
    } on Object {
      await close();
      rethrow;
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    final tunnel = _tunnel;
    final client = _client;
    _tunnel = null;
    _client = null;
    try {
      await tunnel?.close();
    } finally {
      if (client != null) {
        onClientClosing(client);
        await disconnectClient(client);
      }
    }
  }
}
