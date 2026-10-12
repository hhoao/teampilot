import 'dart:async';
import 'dart:convert';

import 'package:acpd/acpd.dart' as acpd;

import 'acp_agent_translator.dart';
import 'acp_frame_logger.dart';
import 'acp_session.dart';
import 'acp_transport.dart';

/// Result of the ACP `initialize` handshake.
class AcpInitializeResult {
  const AcpInitializeResult({
    required this.protocolVersion,
    this.agentName,
    this.agentVersion,
  });

  /// The negotiated protocol version (wire integer, e.g. `1` for ACP v1).
  final int protocolVersion;

  /// The agent's programmatic name from its `agentInfo`, if declared.
  final String? agentName;

  /// The agent's semantic version from its `agentInfo`, if declared.
  final String? agentVersion;
}

/// Which session methods the agent declared support for in `initialize`.
///
/// Mapped from acpd's [acpd.AgentCapabilities]:
/// - `loadSession` ← `AgentCapabilities.loadSession` (bool).
/// - `sessionList` / `sessionResume` / `sessionClose` ← the presence of the
///   matching flag inside `AgentCapabilities.sessionCapabilities` (acpd models
///   these as nullable [acpd.CapabilityFlag]s; absence means unsupported).
/// - `promptStreaming`: ACP v1 has no explicit streaming capability flag —
///   turn updates always stream via `session/update` notifications — so this
///   is reported as `true` for any agent that completed the handshake.
class AcpNegotiatedCapabilities {
  const AcpNegotiatedCapabilities({
    required this.loadSession,
    required this.sessionClose,
    required this.sessionList,
    required this.sessionResume,
    required this.promptStreaming,
  });

  factory AcpNegotiatedCapabilities.fromAgentCapabilities(
    acpd.AgentCapabilities? capabilities,
  ) {
    final sessions = capabilities?.sessionCapabilities;
    return AcpNegotiatedCapabilities(
      loadSession: capabilities?.loadSession ?? false,
      sessionClose: sessions?.close != null,
      sessionList: sessions?.list != null,
      sessionResume: sessions?.resume != null,
      promptStreaming: true,
    );
  }

  /// Whether the agent supports `session/load`.
  final bool loadSession;

  /// Whether the agent supports `session/close`.
  final bool sessionClose;

  /// Whether the agent supports `session/list`.
  final bool sessionList;

  /// Whether the agent supports `session/resume`.
  final bool sessionResume;

  /// Whether prompt updates stream via `session/update` (intrinsic to ACP v1).
  final bool promptStreaming;
}

/// A client-side connection to one running ACP agent process.
///
/// Mounts acpd's [acpd.ClientRole] on an [AcpTransport] byte pipe: outgoing
/// JSON-RPC frames are written as NDJSON lines and logged, incoming lines are
/// decoded into frames and logged, and the agent's stderr is routed to the
/// frame logger without ever touching the protocol channel.
class AcpAgentConnection {
  AcpAgentConnection({
    required AcpTransport transport,
    required AcpFrameLogger logger,
    required this.translator,
    Future<int>? processExitCode,
  }) : _transport = transport,
       _processExitCode = processExitCode {
    _client = acpd.ClientRole().connect(
      _AcpdTransportAdapter(transport, logger),
    );
    _stderrSubscription = transport.stderr.listen(
      (chunk) => logger.logStderr(utf8.decode(chunk, allowMalformed: true)),
    );
    // Claude's adapter emits `_auth/status_update` during `session/new`,
    // before [AcpAgentSession] exists to listen for `session/update`.
    _authRegistration = _client.connection.onNotification(
      '_auth/status_update',
      (params) {
        if (params is! Map) return;
        final notice = parseAcpAuthNotice(
          Map<String, Object?>.from(params),
          method: '_auth/status_update',
        );
        if (notice == null) return;
        lastAuthNotice = notice;
        final session = _openSession;
        if (session == null) {
          _pendingAuth.add(notice);
        } else {
          session.replayAuth(notice);
        }
      },
    );
  }

  final AcpTransport _transport;

  /// Per-agent quirk absorption; consumed by the session layer on stop errors.
  final AcpAgentTranslator translator;

  late final acpd.ClientConnection _client;
  StreamSubscription<List<int>>? _stderrSubscription;
  acpd.HandlerRegistration? _authRegistration;
  final List<AcpAuthNotice> _pendingAuth = [];
  AcpAuthNotice? lastAuthNotice;
  AcpNegotiatedCapabilities? _capabilities;
  bool _disposed = false;

  /// The negotiated capabilities, cached after [initialize].
  ///
  /// Throws [StateError] when read before [initialize] completed.
  AcpNegotiatedCapabilities get capabilities {
    final cached = _capabilities;
    if (cached == null) {
      throw StateError('Capabilities are only available after initialize().');
    }
    return cached;
  }

  /// Whether the connection is still usable.
  bool get isAlive =>
      !_disposed && !_transport.isClosed && !_client.connection.isClosed;

  /// The acpd client connection; consumed by [AcpAgentSession] to subscribe
  /// to session notifications and answer agent requests.
  acpd.ClientConnection get acpdClient => _client;

  /// The agent process's exit code, completing when the process dies.
  ///
  /// Only process-backed transports can observe it; the production spawner
  /// passes the transport's exit-code future in, and it still completes after
  /// the connection is disposed (the chat-side exit watcher relies on that).
  /// Non-process transports (tests) pass nothing — this getter then returns a
  /// future that never completes.
  Future<int> get agentProcessExitCode => _processExitCode ?? _neverExit;

  final Future<int>? _processExitCode;

  /// Future that never completes, for non-process-backed transports.
  static final Future<int> _neverExit = Completer<int>().future;

  /// The session opened via [openSession], if any.
  ///
  /// One connection hosts at most one live session: a second `session/new`
  /// would steal the first session's `session/request_permission` handler
  /// (acpd's `onRequest` replaces), so [openSession] refuses instead.
  AcpAgentSession? _openSession;

  /// Creates a new ACP session via `session/new` for [cwd].
  ///
  /// MCP servers are per-session in ACP and TeamPilot registers none, so the
  /// request always passes an explicit empty list. [permissionTimeout] bounds
  /// how long the session's permission hold waits before auto-rejecting.
  ///
  /// Throws [StateError] when this connection already has an open session;
  /// dispose it first (its [AcpAgentSession.dispose] releases the slot).
  Future<AcpAgentSession> openSession({
    required String cwd,
    Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
  }) async {
    final existing = _openSession;
    if (existing != null) {
      throw StateError(
        'Connection already has an open ACP session '
        '(${existing.sessionId}); dispose it before opening another.',
      );
    }
    final earlyUpdates = <Map<String, Object?>>[];
    final earlyUpdateReg = _client.connection.onNotification('session/update', (
      params,
    ) {
      if (params is Map) {
        earlyUpdates.add(Map<String, Object?>.from(params));
      }
    });
    late final acpd.NewSessionResponse response;
    try {
      response = await _client.client.newSession(
        acpd.NewSessionRequest(cwd: cwd, mcpServers: const []),
      );
    } finally {
      earlyUpdateReg.dispose();
    }
    final session = AcpAgentSession(
      connection: this,
      sessionId: response.sessionId,
      permissionTimeout: permissionTimeout,
    );
    _openSession = session;
    for (final params in earlyUpdates) {
      session.replayRawNotification(params);
    }
    for (final notice in _pendingAuth) {
      session.replayAuth(notice);
    }
    _pendingAuth.clear();
    return session;
  }

  /// Releases the open-session slot; called by [AcpAgentSession.dispose].
  void sessionDisposed(AcpAgentSession session) {
    if (identical(_openSession, session)) _openSession = null;
  }

  /// Runs the `initialize` handshake and caches the negotiated capabilities.
  ///
  /// Advertises no filesystem access (`fs.readTextFile`/`fs.writeTextFile`
  /// false), no terminal support, and registers no MCP servers (ACP carries
  /// MCP servers per session, and TeamPilot registers none).
  Future<AcpInitializeResult> initialize({
    required String clientName,
    required String clientVersion,
    Duration timeout = const Duration(seconds: 30),
    String? authenticateMethodId,
  }) async {
    final response = await _client.client.initialize(
      acpd.InitializeRequest(
        protocolVersion: acpd.ProtocolVersion.v1,
        clientCapabilities: const acpd.ClientCapabilities(
          fs: acpd.FileSystemCapabilities(
            readTextFile: false,
            writeTextFile: false,
          ),
          terminal: false,
        ),
        clientInfo: acpd.Implementation(
          name: clientName,
          version: clientVersion,
        ),
      ),
      timeout: timeout,
    );
    _capabilities = AcpNegotiatedCapabilities.fromAgentCapabilities(
      response.agentCapabilities,
    );
    if (authenticateMethodId != null) {
      await _client.client.authenticate(
        acpd.AuthenticateRequest(methodId: authenticateMethodId),
        timeout: timeout,
      );
    }
    return AcpInitializeResult(
      protocolVersion: response.protocolVersion.value,
      agentName: response.agentInfo?.name,
      agentVersion: response.agentInfo?.version,
    );
  }

  /// Closes the connection and terminates the agent transport.
  ///
  /// Drains the acpd connection (which rejects pending requests), cancels the
  /// stderr subscription, and closes the underlying [AcpTransport].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _authRegistration?.dispose();
    _authRegistration = null;
    _pendingAuth.clear();
    await _stderrSubscription?.cancel();
    await _client.close();
  }
}

/// Adapts our byte-pipe [AcpTransport] to acpd's frame-based [acpd.Transport].
///
/// Decodes the transport's NDJSON byte stream into [acpd.TransportFrame]s
/// (logging every incoming line), and writes outgoing frames as
/// newline-terminated JSON lines (logging every outgoing frame). Malformed
/// input lines become [acpd.MalformedTransportFrame]s, letting acpd's
/// JSON-RPC engine decide whether an error response is warranted — identical
/// to how a real agent process is treated.
class _AcpdTransportAdapter implements acpd.Transport {
  _AcpdTransportAdapter(this._transport, this._logger);

  final AcpTransport _transport;
  final AcpFrameLogger _logger;
  final _incoming = StreamController<acpd.TransportFrame>.broadcast();
  StreamSubscription<String>? _lineSubscription;

  @override
  Stream<acpd.TransportFrame> get incoming {
    _lineSubscription ??= NdjsonDecoder()
        .decode(_transport.input)
        .listen(_onLine, onError: _incoming.addError, onDone: _incoming.close);
    return _incoming.stream;
  }

  void _onLine(String line) {
    _logger.logIncoming(line);
    _incoming.add(acpd.TransportFrame.decode(line));
  }

  @override
  void send(acpd.TransportFrame frame) {
    _logger.logOutgoing(frame.toWire());
    _transport.write(frame.toLine());
  }

  @override
  Future<void> close() async {
    // Order matters: cancelling an async* decode generator that is suspended
    // inside `await for` on a still-open byte stream never completes. Closing
    // the transport first ends the NDJSON source, which drives the generator
    // to completion and lets its subscription cancel cleanly.
    await _transport.close();
    await _lineSubscription?.cancel();
    await _incoming.close();
  }
}
