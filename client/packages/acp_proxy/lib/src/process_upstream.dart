import 'dart:async';
import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:acpd_io/acpd_io.dart';

import 'launch_meta.dart';
import 'process_env.dart';
import 'upstream.dart';
import 'version.dart';

const _proxyClientName = 'teampilot-acp-proxy';

const _forwardedClientMethods = <String>[
  'session/request_permission',
  'cursor/ask_question',
  'cursor/create_plan',
  'cursor/update_todos',
  'cursor/task',
  'cursor/generate_image',
];

const _cursorNotificationMethods = <String>[
  'cursor/update_todos',
  'cursor/task',
  'cursor/generate_image',
];

/// ACP client that owns one CLI process for the life of a proxy session.
///
/// [start] performs `initialize` and, when the launch meta names one,
/// `authenticate`. `session/new` waits until [openNew], after the proxy has
/// subscribed to [updates].
class AcpProcessUpstream implements AcpUpstream {
  AcpProcessUpstream._({
    required Process process,
    required Connection connection,
    required ClientContext client,
    required List<McpServer> mcpServers,
    required Duration killGrace,
    required StreamSubscription<List<int>> stderrSubscription,
  }) : _process = process,
       _connection = connection,
       _client = client,
       _mcpServers = mcpServers,
       _killGrace = killGrace,
       _stderrSubscription = stderrSubscription;

  final Process _process;
  final Connection _connection;
  final ClientContext _client;
  final Duration _killGrace;
  final StreamSubscription<List<int>> _stderrSubscription;
  List<McpServer> _mcpServers;
  String? _sessionId;
  var _alive = true;
  var _nextId = 0;
  Future<void>? _closeFuture;

  final _updates = StreamController<Map<String, Object?>>.broadcast();
  final _requests = StreamController<AcpClientRequest>.broadcast();
  final _pending = <Object, Completer<Map<String, Object?>>>{};

  /// Spawns [meta.executable] and finishes the ACP handshake.
  ///
  /// Empty [meta.env] values are removed. [parentEnvironment] defaults to the
  /// current process environment and is not logged. A handshake failure kills
  /// the process.
  static Future<AcpProcessUpstream> start({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
    Map<String, String>? parentEnvironment,
    Duration handshakeTimeout = const Duration(seconds: 30),
    Duration killGrace = const Duration(seconds: 5),
  }) async {
    final process = await Process.start(
      meta.executable,
      meta.args,
      workingDirectory: cwd,
      environment: mergeAcpProxyProcessEnvironment(
        meta.env,
        parent: parentEnvironment,
      ),
      includeParentEnvironment: false,
      runInShell: false,
    );
    final stderrSubscription = process.stderr.listen((_) {}, onError: (_) {});
    final transport = StdioTransport(
      name: 'acp-cli:${process.pid}',
      input: process.stdout,
      writeOutput: (bytes) {
        process.stdin.add(bytes);
        unawaited(process.stdin.flush().catchError((Object _) {}));
      },
      onClose: () async {
        try {
          await process.stdin.flush();
        } on Object {
          // The pipe may already be closed.
        }
        try {
          await process.stdin.close();
        } on Object {
          // Closing a finished process is not a second failure.
        }
      },
    );
    final connection = Connection(transport);
    final upstream = AcpProcessUpstream._(
      process: process,
      connection: connection,
      client: ClientContext(connection),
      mcpServers: [for (final server in mcpServers) McpServer.fromJson(server)],
      killGrace: killGrace,
      stderrSubscription: stderrSubscription,
    );
    upstream._bind();
    try {
      await upstream._handshake(meta, handshakeTimeout);
    } on Object {
      await upstream.close();
      rethrow;
    }
    return upstream;
  }

  @override
  bool get alive => _alive;

  @override
  Stream<Map<String, Object?>> get updates => _updates.stream;

  @override
  Stream<AcpClientRequest> get clientRequests => _requests.stream;

  @override
  Future<String> openNew({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    _mcpServers = [for (final server in mcpServers) McpServer.fromJson(server)];
    final response = await _client.newSession(
      NewSessionRequest(cwd: cwd, mcpServers: _mcpServers),
    );
    _sessionId = response.sessionId;
    return response.sessionId;
  }

  @override
  Future<void> openLoad({
    required String sessionId,
    required String cwd,
  }) async {
    await _client.loadSession(
      LoadSessionRequest(
        sessionId: sessionId,
        cwd: cwd,
        mcpServers: _mcpServers,
      ),
    );
    _sessionId = sessionId;
  }

  @override
  Future<void> prompt(String text) async {
    final sessionId = _sessionId;
    if (sessionId == null) throw StateError('no cli session');
    final response = await _client.prompt(PromptRequest.text(sessionId, text));
    if (_updates.isClosed) return;
    _updates.add({
      'sessionUpdate': 'stop',
      'stopReason': response.stopReason.toJson(),
    });
  }

  @override
  Future<void> cancel() async {
    final sessionId = _sessionId;
    if (sessionId == null || !_alive) return;
    _client.cancel(sessionId);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  @override
  void completeClientRequest(Object id, Map<String, Object?> result) {
    final pending = _pending.remove(id);
    if (pending == null || pending.isCompleted) return;
    pending.complete(Map<String, Object?>.from(result));
  }

  Future<void> _handshake(
    AcpProxyLaunchMeta meta,
    Duration handshakeTimeout,
  ) async {
    await _client.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.v1,
        clientCapabilities: const ClientCapabilities(
          fs: FileSystemCapabilities(readTextFile: false, writeTextFile: false),
          terminal: false,
        ),
        clientInfo: Implementation(
          name: _proxyClientName,
          version: acpProxyVersion,
        ),
      ),
      timeout: handshakeTimeout,
    );
    final methodId = meta.authenticateMethodId;
    if (methodId == null) return;
    await _client.authenticate(
      AuthenticateRequest(methodId: methodId),
      timeout: handshakeTimeout,
    );
  }

  void _bind() {
    unawaited(
      _process.exitCode.then<void>((_) {
        _alive = false;
        _failPending();
        if (_closeFuture == null) {
          unawaited(_connection.close().catchError((Object _) {}));
        }
        _finishStreams();
      }),
    );
    _connection.onNotification('session/update', (params) {
      if (_updates.isClosed) return;
      final update = _objectMap(params)['update'];
      if (update is! Map) return;
      _updates.add(Map<String, Object?>.from(update));
    });
    for (final method in _forwardedClientMethods) {
      _connection.onRequest(method, (params) => _forward(method, params));
    }
    for (final method in _cursorNotificationMethods) {
      _connection.onNotification(method, (params) {
        if (_requests.isClosed) return;
        _requests.add(
          AcpClientRequest(
            id: 'n${_nextId++}',
            method: method,
            params: _objectMap(params),
          ),
        );
      });
    }
  }

  Future<Map<String, Object?>> _forward(String method, Object? params) {
    if (_requests.isClosed) return Future.value(const {});
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _requests.add(
      AcpClientRequest(id: id, method: method, params: _objectMap(params)),
    );
    return completer.future;
  }

  Future<void> _close() async {
    _alive = false;
    _failPending();
    try {
      await _connection.close();
    } on Object {
      // The CLI may already have closed its stdout.
    }
    try {
      await _signalTree(_process, ProcessSignal.sigterm);
      await _process.exitCode.timeout(_killGrace);
    } on TimeoutException {
      try {
        await _signalTree(_process, ProcessSignal.sigkill);
      } on Object {
        // The process can exit between the two signals.
      }
      await _process.exitCode;
    } on Object {
      // exitCode can fail when the process is already gone.
    }
    try {
      await _stderrSubscription.cancel();
    } on Object {
      // The stderr pipe closes with the process.
    }
    _finishStreams();
  }

  void _failPending() {
    final pending = List<Completer<Map<String, Object?>>>.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('cli closed'));
      }
    }
  }

  void _finishStreams() {
    if (!_updates.isClosed) _updates.close();
    if (!_requests.isClosed) _requests.close();
  }
}

Map<String, Object?> _objectMap(Object? raw) {
  if (raw is Map<String, Object?>) return Map<String, Object?>.from(raw);
  if (raw is Map) return Map<String, Object?>.from(raw);
  return <String, Object?>{};
}

Future<void> _signalTree(Process process, ProcessSignal signal) async {
  if (Platform.isWindows) {
    final arguments = <String>['/PID', '${process.pid}', '/T'];
    if (signal == ProcessSignal.sigkill) arguments.add('/F');
    await Process.run('taskkill', arguments, runInShell: false);
    return;
  }
  final descendants = await _descendantPids(process.pid);
  for (final pid in descendants.reversed) {
    try {
      Process.killPid(pid, signal);
    } on Object {
      // A child that already exited is not a close failure.
    }
  }
  try {
    process.kill(signal);
  } on Object {
    // The CLI can exit before the signal is delivered.
  }
}

Future<List<int>> _descendantPids(int rootPid) async {
  final result = await Process.run('ps', const [
    '-axo',
    'pid=,ppid=',
  ], runInShell: false);
  if (result.exitCode != 0) return const [];
  final children = <int, List<int>>{};
  for (final line in '${result.stdout}'.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 2) continue;
    final pid = int.tryParse(fields[0]);
    final parent = int.tryParse(fields[1]);
    if (pid == null || parent == null) continue;
    children.putIfAbsent(parent, () => <int>[]).add(pid);
  }
  final descendants = <int>[];
  final seen = <int>{rootPid};
  void collect(int parent) {
    for (final child in children[parent] ?? const <int>[]) {
      if (!seen.add(child)) continue;
      descendants.add(child);
      collect(child);
    }
  }

  collect(rootPid);
  return descendants;
}
