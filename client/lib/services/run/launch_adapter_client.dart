import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/run/launch_type_contribution.dart';
import '../../utils/logging/logger.dart';
import 'launch_adapter_protocol.dart';

part 'launch_adapter_connection.dart';

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

  /// Sticky adapters only — keyed by `(type, targetId)`.
  final Map<_StickyPoolKey, _AdapterConnection> _stickyPool = {};

  /// Oneshot adapters — one process per session; never share sticky keys.
  final Map<String, _AdapterConnection> _oneshotBySession = {};

  final Map<String, Completer<LaunchAdapterExitedEvent>> _exitWaiters = {};
  final Map<String, LaunchAdapterExitedEvent> _exitedEvents = {};
  final Map<String, _AdapterConnection> _sessionConnection = {};

  final StreamController<LaunchAdapterOutputEvent> _outputController =
      StreamController<LaunchAdapterOutputEvent>.broadcast();
  final StreamController<LaunchAdapterOptionsChangedEvent>
  _optionsChangedController =
      StreamController<LaunchAdapterOptionsChangedEvent>.broadcast();
  final StreamController<LaunchAdapterConfigurationsChangedEvent>
  _configurationsChangedController =
      StreamController<LaunchAdapterConfigurationsChangedEvent>.broadcast();
  final StreamController<LaunchAdapterExitedEvent> _exitedController =
      StreamController<LaunchAdapterExitedEvent>.broadcast();
  final StreamController<LaunchAdapterErrorEvent> _errorController =
      StreamController<LaunchAdapterErrorEvent>.broadcast();

  Stream<LaunchAdapterOutputEvent> get outputStream => _outputController.stream;
  Stream<LaunchAdapterOptionsChangedEvent> get optionsChanged =>
      _optionsChangedController.stream;
  Stream<LaunchAdapterConfigurationsChangedEvent> get configurationsChanged =>
      _configurationsChangedController.stream;
  Stream<LaunchAdapterExitedEvent> get exited => _exitedController.stream;
  Stream<LaunchAdapterErrorEvent> get errorStream => _errorController.stream;

  /// Ensures a sticky adapter is initialized for `(type, targetId)`.
  ///
  /// Oneshot lifecycle is a no-op here — oneshot processes are spawned per
  /// [launch] so concurrent sessions never share a pool slot.
  Future<void> initialize({
    required String type,
    required String targetId,
    required String adapterCommand,
    String? extensionId,
    LaunchAdapterLifecycle lifecycle = LaunchAdapterLifecycle.sticky,
  }) async {
    if (lifecycle == LaunchAdapterLifecycle.oneshot) {
      return;
    }

    final key = _StickyPoolKey(type, targetId);
    final existing = _stickyPool[key];
    if (existing != null &&
        !existing.closed &&
        existing.initialized) {
      return;
    }

    if (existing != null) {
      await _disposeConnection(existing);
    }

    final connection = await _spawnConnection(
      type: type,
      targetId: targetId,
      adapterCommand: adapterCommand,
      extensionId: extensionId,
      lifecycle: LaunchAdapterLifecycle.sticky,
    );
    _stickyPool[key] = connection;

    try {
      await _request(
        connection,
        method: LaunchAdapterProtocol.methodInitialize,
        params: {'protocolVersion': 1},
        timeout: _initializeTimeout,
        killOnTimeout: true,
      );
      connection.initialized = true;
    } catch (_) {
      await _disposeConnection(connection);
      rethrow;
    }
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

    final _AdapterConnection connection;
    if (lifecycle == LaunchAdapterLifecycle.oneshot) {
      connection = await _spawnConnection(
        type: resolvedType,
        targetId: resolvedTarget,
        adapterCommand: adapterCommand ?? '',
        extensionId: extensionId,
        lifecycle: LaunchAdapterLifecycle.oneshot,
        oneshotSessionId: sessionId,
      );
      _oneshotBySession[sessionId] = connection;
      try {
        await _request(
          connection,
          method: LaunchAdapterProtocol.methodInitialize,
          params: {'protocolVersion': 1},
          timeout: _initializeTimeout,
          killOnTimeout: true,
        );
        connection.initialized = true;
      } catch (_) {
        await _disposeConnection(connection);
        rethrow;
      }
    } else {
      final key = _StickyPoolKey(resolvedType, resolvedTarget);
      if (!_stickyPool.containsKey(key)) {
        await initialize(
          type: resolvedType,
          targetId: resolvedTarget,
          adapterCommand: adapterCommand ?? '',
          extensionId: extensionId,
          lifecycle: LaunchAdapterLifecycle.sticky,
        );
      }
      final sticky = _stickyPool[key];
      if (sticky == null || sticky.closed) {
        throw StateError(
          'adapter not initialized for $resolvedType@$resolvedTarget',
        );
      }
      connection = sticky;
    }

    connection.activeSessions.add(sessionId);
    _sessionConnection[sessionId] = connection;
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
        killOnTimeout: true,
      );
    } catch (error) {
      connection.activeSessions.remove(sessionId);
      _sessionConnection.remove(sessionId);
      final waiter = _exitWaiters.remove(sessionId);
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(error);
      }
      if (connection.isOneshot) {
        await _disposeConnection(connection);
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
    final connection = _requireStickyConnection(
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
    required String type,
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    String targetId = 'local',
  }) async {
    final connection = _requireStickyConnection(
      type: type,
      targetId: targetId,
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
    final connection = _sessionConnection[sessionId];
    if (connection == null || connection.closed) return;

    await _request(
      connection,
      method: LaunchAdapterProtocol.methodStop,
      params: {'sessionId': sessionId},
      timeout: _requestTimeout,
    );
  }

  Future<LaunchAdapterExitedEvent> waitExited(String sessionId) {
    final already = _exitedEvents.remove(sessionId);
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
    final key = _StickyPoolKey(type, targetId);
    final connection = _stickyPool[key];
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
    await _disposeConnection(connection);
  }

  Future<void> dispose() async {
    final sticky = _stickyPool.values.toList();
    final oneshot = _oneshotBySession.values.toList();
    for (final connection in [...sticky, ...oneshot]) {
      await _disposeConnection(connection);
    }
    await _outputController.close();
    await _optionsChangedController.close();
    await _configurationsChangedController.close();
    await _exitedController.close();
    await _errorController.close();
  }

  Future<_AdapterConnection> _spawnConnection({
    required String type,
    required String targetId,
    required String adapterCommand,
    required LaunchAdapterLifecycle lifecycle,
    String? extensionId,
    String? oneshotSessionId,
  }) async {
    final expanded = LaunchAdapterProtocol.expandAdapterCommand(
      command: adapterCommand,
      extensionId: extensionId,
      resolver: _extensionPathResolver,
    );
    final (executable, arguments) = LaunchAdapterProtocol.splitCommand(
      expanded,
    );
    final process = await _startProcess(command: executable, args: arguments);
    final connection = _AdapterConnection(
      process: process,
      lifecycle: lifecycle,
      type: type,
      targetId: targetId,
      oneshotSessionId: oneshotSessionId,
    );
    _attachReaders(connection);
    unawaited(
      process.exitCode.then((code) {
        _onProcessExit(connection, code);
      }),
    );
    return connection;
  }

  _AdapterConnection _requireStickyConnection({
    required String type,
    required String targetId,
  }) {
    final connection = _stickyPool[_StickyPoolKey(type, targetId)];
    if (connection == null || connection.closed || !connection.initialized) {
      throw StateError('adapter not initialized for $type@$targetId');
    }
    return connection;
  }

  void _attachReaders(_AdapterConnection connection) {
    connection.stdoutSub = connection.process.stdout
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
    connection.stderrSub = connection.process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim().isEmpty) return;
          AppLogger.instance.w(
            '[LaunchAdapter] stderr ${connection.type}@${connection.targetId}: $line',
          );
        });
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
            LaunchAdapterOptionsChangedEvent(
              type: connection.type,
              targetId: connection.targetId,
              options: LaunchAdapterProtocol.parseOptions(params['options']),
            ),
          );
        }
      case LaunchAdapterProtocol.notifyConfigurationsChanged:
        if (!_configurationsChangedController.isClosed) {
          _configurationsChangedController.add(
            LaunchAdapterConfigurationsChangedEvent(
              type: connection.type,
              targetId: connection.targetId,
              configurations: LaunchAdapterProtocol.parseConfigurationEntries(
                params['configurations'],
              ),
            ),
          );
        }
      case LaunchAdapterProtocol.notifyError:
        final sessionId = params['sessionId']?.toString();
        final messageText = params['message']?.toString() ?? 'adapter error';
        _emitError(
          LaunchAdapterErrorEvent(
            type: connection.type,
            targetId: connection.targetId,
            message: messageText,
            sessionId: sessionId,
          ),
        );
        if (sessionId != null && sessionId.isNotEmpty) {
          _failSession(sessionId, StateError(messageText));
        }
    }
  }

  void _handleExited(
    _AdapterConnection connection,
    LaunchAdapterExitedEvent event,
  ) {
    connection.activeSessions.remove(event.sessionId);
    _sessionConnection.remove(event.sessionId);
    // Always retain until waitExited consumes — launch may complete after exited.
    _exitedEvents[event.sessionId] = event;
    if (!_exitedController.isClosed) {
      _exitedController.add(event);
    }
    final waiter = _exitWaiters.remove(event.sessionId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(event);
    }

    if (connection.isOneshot) {
      unawaited(_disposeConnection(connection));
    }
  }

  void _failSession(String sessionId, Object error) {
    final waiter = _exitWaiters.remove(sessionId);
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(error);
    }
    _sessionConnection.remove(sessionId);
    _exitedEvents.remove(sessionId);
  }

  void _emitError(LaunchAdapterErrorEvent event) {
    if (!_errorController.isClosed) {
      _errorController.add(event);
    }
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
      _sessionConnection.remove(sessionId);
      _emitError(
        LaunchAdapterErrorEvent(
          type: connection.type,
          targetId: connection.targetId,
          message: message,
          sessionId: sessionId,
        ),
      );
    }

    if (sessions.isEmpty) {
      _emitError(
        LaunchAdapterErrorEvent(
          type: connection.type,
          targetId: connection.targetId,
          message: message,
        ),
      );
    }

    unawaited(_disposeConnection(connection));
  }

  Future<Map<String, Object?>> _request(
    _AdapterConnection connection, {
    required String method,
    required Map<String, Object?> params,
    required Duration timeout,
    bool killOnTimeout = false,
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
      if (killOnTimeout) {
        await _disposeConnection(connection);
      }
      throw TimeoutException('Launch adapter $method timed out', timeout);
    }
  }

  Future<void> _disposeConnection(_AdapterConnection connection) async {
    connection.closed = true;

    final stickyKey = _StickyPoolKey(connection.type, connection.targetId);
    if (_stickyPool[stickyKey] == connection) {
      _stickyPool.remove(stickyKey);
    }
    final oneshotId = connection.oneshotSessionId;
    if (oneshotId != null && _oneshotBySession[oneshotId] == connection) {
      _oneshotBySession.remove(oneshotId);
    }

    await connection.stdoutSub?.cancel();
    await connection.stderrSub?.cancel();
    connection.stdoutSub = null;
    connection.stderrSub = null;
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
