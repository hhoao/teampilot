import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/run/launch_type_contribution.dart';
import 'launch_adapter_protocol.dart';

/// stdin/stdout handle for one Launch Adapter child process.
class LaunchAdapterProcess {
  LaunchAdapterProcess({
    required this.stdin,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required this.exitCode,
    required void Function([ProcessSignal signal]) kill,
  }) : _stdout = stdout,
       _stderr = stderr,
       _kill = kill;

  factory LaunchAdapterProcess.fromIo({
    required IOSink stdin,
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required Future<int> exitCode,
    required void Function([ProcessSignal signal]) kill,
  }) {
    return LaunchAdapterProcess(
      stdin: stdin,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      kill: kill,
    );
  }

  final IOSink stdin;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final Future<int> exitCode;
  final void Function([ProcessSignal signal]) _kill;

  Stream<List<int>> get stdout => _stdout;
  Stream<List<int>> get stderr => _stderr;

  void kill([ProcessSignal signal = ProcessSignal.sigterm]) => _kill(signal);
}

/// Spawns (or returns) an adapter process for the given expanded command.
typedef LaunchAdapterProcessStarter =
    Future<LaunchAdapterProcess> Function({
      required String command,
      required List<String> args,
    });

class _PoolKey {
  const _PoolKey(this.type, this.targetId);

  final String type;
  final String targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PoolKey && type == other.type && targetId == other.targetId;

  @override
  int get hashCode => Object.hash(type, targetId);
}

class _PendingRequest {
  _PendingRequest(this.completer);

  final Completer<Map<String, Object?>> completer;
}

class _AdapterConnection {
  _AdapterConnection({
    required this.process,
    required this.lifecycle,
    required this.type,
    required this.targetId,
  });

  final LaunchAdapterProcess process;
  final LaunchAdapterLifecycle lifecycle;
  final String type;
  final String targetId;

  final Map<Object, _PendingRequest> pending = {};
  final Set<String> activeSessions = {};
  var nextId = 1;
  var initialized = false;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  var closed = false;

  Object allocId() => nextId++;
}

/// JSON-RPC Launch Adapter client with sticky/oneshot process pooling.
class LaunchAdapterClient {
  LaunchAdapterClient({
    required ExtensionPathResolver extensionPathResolver,
    LaunchAdapterProcessStarter? startProcess,
    Duration? initializeTimeout,
    Duration? launchTimeout,
    Duration? requestTimeout,
  }) : _extensionPathResolver = extensionPathResolver,
       _startProcess = startProcess ?? _defaultStartProcess,
       _initializeTimeout =
           initializeTimeout ?? LaunchAdapterTimeouts.initialize,
       _launchTimeout = launchTimeout ?? LaunchAdapterTimeouts.launch,
       _requestTimeout = requestTimeout ?? LaunchAdapterTimeouts.request;

  final ExtensionPathResolver _extensionPathResolver;
  final LaunchAdapterProcessStarter _startProcess;
  final Duration _initializeTimeout;
  final Duration _launchTimeout;
  final Duration _requestTimeout;

  final Map<_PoolKey, _AdapterConnection> _pool = {};
  final Map<String, Completer<LaunchAdapterExitedEvent>> _exitWaiters = {};
  final Map<String, LaunchAdapterExitedEvent> _exitedEvents = {};
  final Map<String, _PoolKey> _sessionPool = {};

  final StreamController<LaunchAdapterOutputEvent> _outputController =
      StreamController<LaunchAdapterOutputEvent>.broadcast();
  final StreamController<List<LaunchOption>> _optionsChangedController =
      StreamController<List<LaunchOption>>.broadcast();
  final StreamController<List<LaunchAdapterConfigurationEntry>>
  _configurationsChangedController =
      StreamController<List<LaunchAdapterConfigurationEntry>>.broadcast();
  final StreamController<LaunchAdapterExitedEvent> _exitedController =
      StreamController<LaunchAdapterExitedEvent>.broadcast();

  Stream<LaunchAdapterOutputEvent> get outputStream => _outputController.stream;
  Stream<List<LaunchOption>> get optionsChanged =>
      _optionsChangedController.stream;
  Stream<List<LaunchAdapterConfigurationEntry>> get configurationsChanged =>
      _configurationsChangedController.stream;
  Stream<LaunchAdapterExitedEvent> get exited => _exitedController.stream;

  /// Ensures a sticky (or fresh oneshot) adapter is initialized for the key.
  Future<void> initialize({
    required String type,
    required String targetId,
    required String adapterCommand,
    String? extensionId,
    LaunchAdapterLifecycle lifecycle = LaunchAdapterLifecycle.sticky,
  }) async {
    final key = _PoolKey(type, targetId);
    final existing = _pool[key];
    if (existing != null &&
        !existing.closed &&
        existing.initialized &&
        lifecycle == LaunchAdapterLifecycle.sticky) {
      return;
    }

    if (existing != null) {
      await _disposeConnection(existing, removeFromPool: true);
    }

    final expanded = LaunchAdapterProtocol.expandAdapterCommand(
      command: adapterCommand,
      extensionId: extensionId,
      resolver: _extensionPathResolver,
    );
    final (executable, arguments) = LaunchAdapterProtocol.splitCommand(expanded);
    final process = await _startProcess(command: executable, args: arguments);
    final connection = _AdapterConnection(
      process: process,
      lifecycle: lifecycle,
      type: type,
      targetId: targetId,
    );
    _pool[key] = connection;
    _attachReaders(connection);

    unawaited(
      process.exitCode.then((code) {
        _onProcessExit(connection, code);
      }),
    );

    await _request(
      connection,
      method: LaunchAdapterProtocol.methodInitialize,
      params: {'protocolVersion': 1},
      timeout: _initializeTimeout,
    );
    connection.initialized = true;
  }

  Future<void> launch({
    required String sessionId,
    required Map<String, Object?> configuration,
    String? type,
    String? targetId,
    String? adapterCommand,
    String? extensionId,
    LaunchAdapterLifecycle lifecycle = LaunchAdapterLifecycle.sticky,
  }) async {
    final resolvedType = type ?? configuration['type']?.toString() ?? '';
    final resolvedTarget = targetId ?? 'local';
    final key = _PoolKey(resolvedType, resolvedTarget);

    if (lifecycle == LaunchAdapterLifecycle.oneshot || !_pool.containsKey(key)) {
      final command = adapterCommand ?? '';
      await initialize(
        type: resolvedType,
        targetId: resolvedTarget,
        adapterCommand: command,
        extensionId: extensionId,
        lifecycle: lifecycle,
      );
    }

    final connection = _pool[key];
    if (connection == null || connection.closed) {
      throw StateError('adapter not initialized for $resolvedType@$resolvedTarget');
    }

    connection.activeSessions.add(sessionId);
    _sessionPool[sessionId] = key;
    _exitWaiters.putIfAbsent(
      sessionId,
      () => Completer<LaunchAdapterExitedEvent>(),
    );

    try {
      await _request(
        connection,
        method: LaunchAdapterProtocol.methodLaunch,
        params: {
          'sessionId': sessionId,
          'configuration': configuration,
        },
        timeout: _launchTimeout,
      );
    } catch (error) {
      connection.activeSessions.remove(sessionId);
      _sessionPool.remove(sessionId);
      final waiter = _exitWaiters.remove(sessionId);
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(error);
      }
      rethrow;
    }
  }

  Future<List<LaunchOption>> provideOptions({
    required String configurationId,
    required Map<String, Object?> configuration,
    String? type,
    String? targetId,
  }) async {
    final connection = _requireConnection(
      type: type ?? configuration['type']?.toString() ?? '',
      targetId: targetId ?? 'local',
    );
    final result = await _request(
      connection,
      method: LaunchAdapterProtocol.methodProvideOptions,
      params: {
        'configurationId': configurationId,
        'configuration': configuration,
      },
      timeout: _requestTimeout,
    );
    return LaunchAdapterProtocol.parseOptions(result['options']);
  }

  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    String? type,
    String? targetId,
  }) async {
    final connection = _requireConnection(
      type: type ?? 'flutter',
      targetId: targetId ?? 'local',
    );
    final response = await _request(
      connection,
      method: LaunchAdapterProtocol.methodConfigureAction,
      params: {
        'actionId': actionId,
        'workspaceFolder': workspaceFolder,
        'result': result,
      },
      timeout: _requestTimeout,
    );
    return ConfigureActionResult.fromJson(response);
  }

  Future<void> stop(String sessionId) async {
    final key = _sessionPool[sessionId];
    if (key == null) return;
    final connection = _pool[key];
    if (connection == null || connection.closed) return;

    await _request(
      connection,
      method: LaunchAdapterProtocol.methodStop,
      params: {'sessionId': sessionId},
      timeout: _requestTimeout,
    );
  }

  Future<LaunchAdapterExitedEvent> waitExited(String sessionId) {
    final already = _exitedEvents[sessionId];
    if (already != null) return Future.value(already);
    final existing = _exitWaiters[sessionId];
    if (existing != null) return existing.future;
    final completer = Completer<LaunchAdapterExitedEvent>();
    _exitWaiters[sessionId] = completer;
    return completer.future;
  }

  Future<void> shutdown({
    required String type,
    required String targetId,
  }) async {
    final key = _PoolKey(type, targetId);
    final connection = _pool[key];
    if (connection == null) return;
    try {
      if (!connection.closed) {
        await _request(
          connection,
          method: LaunchAdapterProtocol.methodShutdown,
          params: const {},
          timeout: _requestTimeout,
        );
      }
    } catch (_) {
      // Best-effort shutdown.
    }
    await _disposeConnection(connection, removeFromPool: true);
  }

  Future<void> dispose() async {
    final connections = _pool.values.toList();
    for (final connection in connections) {
      await _disposeConnection(connection, removeFromPool: true);
    }
    await _outputController.close();
    await _optionsChangedController.close();
    await _configurationsChangedController.close();
    await _exitedController.close();
  }

  _AdapterConnection _requireConnection({
    required String type,
    required String targetId,
  }) {
    final connection = _pool[_PoolKey(type, targetId)];
    if (connection == null || connection.closed || !connection.initialized) {
      throw StateError('adapter not initialized for $type@$targetId');
    }
    return connection;
  }

  void _attachReaders(_AdapterConnection connection) {
    connection._stdoutSub = connection.process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => _onLine(connection, line),
          onError: (_) => _failConnection(connection, 'adapter stdout error'),
          onDone: () {
            if (!connection.closed) {
              _failConnection(connection, 'adapter stdout closed');
            }
          },
        );
    connection._stderrSub = connection.process.stderr.listen((_) {});
  }

  void _onLine(_AdapterConnection connection, String line) {
    final message = LaunchAdapterProtocol.decodeLine(line);
    if (message == null) return;

    if (LaunchAdapterProtocol.isResponse(message)) {
      final id = message['id'];
      if (id == null) return;
      final pending = connection.pending.remove(id);
      if (pending == null) return;
      if (message.containsKey('error')) {
        final error = message['error'];
        final text = error is Map
            ? (error['message']?.toString() ?? error.toString())
            : error?.toString() ?? 'adapter error';
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(StateError(text));
        }
        return;
      }
      final result = message['result'];
      if (!pending.completer.isCompleted) {
        pending.completer.complete(
          result is Map
              ? Map<String, Object?>.from(result)
              : <String, Object?>{},
        );
      }
      return;
    }

    if (!LaunchAdapterProtocol.isNotification(message)) return;
    final method = message['method'] as String;
    final params = LaunchAdapterProtocol.paramsOf(message);
    switch (method) {
      case LaunchAdapterProtocol.notifyOutput:
        if (!_outputController.isClosed) {
          _outputController.add(LaunchAdapterOutputEvent.fromParams(params));
        }
      case LaunchAdapterProtocol.notifyExited:
        _handleExited(connection, LaunchAdapterExitedEvent.fromParams(params));
      case LaunchAdapterProtocol.notifyOptionsChanged:
        if (!_optionsChangedController.isClosed) {
          _optionsChangedController.add(
            LaunchAdapterProtocol.parseOptions(params['options']),
          );
        }
      case LaunchAdapterProtocol.notifyConfigurationsChanged:
        if (!_configurationsChangedController.isClosed) {
          _configurationsChangedController.add(
            LaunchAdapterProtocol.parseConfigurationEntries(
              params['configurations'],
            ),
          );
        }
      case LaunchAdapterProtocol.notifyError:
        final sessionId = params['sessionId']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          _failSession(
            sessionId,
            StateError(params['message']?.toString() ?? 'adapter error'),
          );
        }
    }
  }

  void _handleExited(
    _AdapterConnection connection,
    LaunchAdapterExitedEvent event,
  ) {
    connection.activeSessions.remove(event.sessionId);
    _sessionPool.remove(event.sessionId);
    _exitedEvents[event.sessionId] = event;
    if (!_exitedController.isClosed) {
      _exitedController.add(event);
    }
    final waiter = _exitWaiters.remove(event.sessionId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(event);
    }

    if (connection.lifecycle == LaunchAdapterLifecycle.oneshot) {
      unawaited(_disposeConnection(connection, removeFromPool: true));
    }
  }

  void _failSession(String sessionId, Object error) {
    final waiter = _exitWaiters.remove(sessionId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(error);
    }
    _sessionPool.remove(sessionId);
  }

  void _onProcessExit(_AdapterConnection connection, int code) {
    if (connection.closed) return;
    _failConnection(
      connection,
      'adapter process exited with code $code',
      exitCode: code,
    );
  }

  void _failConnection(
    _AdapterConnection connection,
    String message, {
    int exitCode = 1,
  }) {
    if (connection.closed) return;
    connection.closed = true;

    for (final pending in connection.pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError(message));
      }
    }
    connection.pending.clear();

    final sessions = connection.activeSessions.toList();
    connection.activeSessions.clear();
    for (final sessionId in sessions) {
      final event = LaunchAdapterExitedEvent(
        sessionId: sessionId,
        exitCode: exitCode,
      );
      _exitedEvents[sessionId] = event;
      if (!_exitedController.isClosed) {
        _exitedController.add(event);
      }
      final waiter = _exitWaiters.remove(sessionId);
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete(event);
      }
      _sessionPool.remove(sessionId);
    }

    final key = _PoolKey(connection.type, connection.targetId);
    if (_pool[key] == connection) {
      _pool.remove(key);
    }
    unawaited(_disposeConnection(connection, removeFromPool: false));
  }

  Future<Map<String, Object?>> _request(
    _AdapterConnection connection, {
    required String method,
    required Map<String, Object?> params,
    required Duration timeout,
  }) async {
    if (connection.closed) {
      throw StateError('adapter connection closed');
    }
    final id = connection.allocId();
    final pending = _PendingRequest(Completer<Map<String, Object?>>());
    connection.pending[id] = pending;
    connection.process.stdin.writeln(
      LaunchAdapterProtocol.encodeRequest(
        id: id,
        method: method,
        params: params,
      ),
    );
    await connection.process.stdin.flush();
    try {
      return await pending.completer.future.timeout(timeout);
    } on TimeoutException {
      connection.pending.remove(id);
      throw TimeoutException('Launch adapter $method timed out', timeout);
    }
  }

  Future<void> _disposeConnection(
    _AdapterConnection connection, {
    required bool removeFromPool,
  }) async {
    connection.closed = true;
    if (removeFromPool) {
      final key = _PoolKey(connection.type, connection.targetId);
      if (_pool[key] == connection) {
        _pool.remove(key);
      }
    }
    await connection._stdoutSub?.cancel();
    await connection._stderrSub?.cancel();
    connection._stdoutSub = null;
    connection._stderrSub = null;
    try {
      connection.process.kill();
    } catch (_) {}
    for (final pending in connection.pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('adapter disposed'));
      }
    }
    connection.pending.clear();
  }

  static Future<LaunchAdapterProcess> _defaultStartProcess({
    required String command,
    required List<String> args,
  }) async {
    final process = await Process.start(command, args);
    return LaunchAdapterProcess.fromIo(
      stdin: process.stdin,
      stdout: process.stdout,
      stderr: process.stderr,
      exitCode: process.exitCode,
      kill: process.kill,
    );
  }
}
