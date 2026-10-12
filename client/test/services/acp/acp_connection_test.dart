import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_connection.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/acp/acp_transport.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  late acpd_test.MockAgent agent;
  late _PairAcpTransport transport;
  late AcpFrameLogger logger;
  late AcpAgentConnection conn;

  setUp(() {
    agent = acpd_test.MockAgent();
    transport = _PairAcpTransport(agent.clientTransport);
    logger = AcpFrameLogger(enableDiskLog: false);
    conn = AcpAgentConnection(
      transport: transport,
      logger: logger,
      translator: const GeminiAcpTranslator(),
    );
  });

  tearDown(() async {
    await conn.dispose();
    await agent.close();
  });

  acpd_test.MockAgent stubInitialize({
    acpd.AgentCapabilities agentCapabilities = const acpd.AgentCapabilities(),
  }) {
    agent.connection.onRequest('initialize', (params) {
      return acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
        agentInfo: const acpd.Implementation(
          name: 'mock-agent',
          version: '9.9',
        ),
        agentCapabilities: agentCapabilities,
      ).toJson();
    });
    return agent;
  }

  test('initialize handshake caches agent capabilities', () async {
    stubInitialize(
      agentCapabilities: const acpd.AgentCapabilities(
        loadSession: true,
        sessionCapabilities: acpd.SessionCapabilities(
          list: acpd.CapabilityFlag(),
          resume: acpd.CapabilityFlag(),
          close: acpd.CapabilityFlag(),
        ),
      ),
    );

    final result = await conn.initialize(
      clientName: 'teampilot',
      clientVersion: '1.0.0',
    );

    expect(result.protocolVersion, 1);
    expect(result.agentName, 'mock-agent');
    expect(result.agentVersion, '9.9');

    expect(conn.capabilities.loadSession, isTrue);
    expect(conn.capabilities.sessionList, isTrue);
    expect(conn.capabilities.sessionResume, isTrue);
    expect(conn.capabilities.sessionClose, isTrue);

    expect(conn.isAlive, isTrue);
  });

  test('advertises no fs/terminal client capabilities', () async {
    acpd.InitializeRequest? seen;
    agent.connection.onRequest('initialize', (params) {
      seen = acpd.InitializeRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return const acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
      ).toJson();
    });

    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

    expect(seen!.clientInfo?.name, 'teampilot');
    expect(seen!.clientInfo?.version, '1.0.0');
    final caps = seen!.clientCapabilities!;
    expect(caps.fs?.readTextFile, isFalse);
    expect(caps.fs?.writeTextFile, isFalse);
    expect(caps.terminal, isFalse);
    expect(caps.session, isNull);
  });

  test('capabilities default to false when agent declares nothing', () async {
    stubInitialize();

    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

    expect(conn.capabilities.loadSession, isFalse);
    expect(conn.capabilities.sessionList, isFalse);
    expect(conn.capabilities.sessionResume, isFalse);
    expect(conn.capabilities.sessionClose, isFalse);
  });

  test('logs outgoing and incoming frames', () async {
    stubInitialize();

    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

    final outgoing = logger.snapshot(direction: AcpFrameDirection.outgoing);
    expect(outgoing, isNotEmpty);
    expect(outgoing.first, contains('"initialize"'));
    expect(outgoing.first, contains('"teampilot"'));

    final incoming = logger.snapshot(direction: AcpFrameDirection.incoming);
    expect(incoming, isNotEmpty);
    expect(incoming.first, contains('mock-agent'));
  });

  test('routes stderr lines to the frame logger', () async {
    stubInitialize();
    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

    transport.emitStderr('gemini: warm boot\n');

    await pumpEventQueue();
    expect(
      logger.snapshot(direction: AcpFrameDirection.stderr),
      contains('gemini: warm boot\n'),
    );
  });

  test('dispose closes the transport and marks the connection dead', () async {
    stubInitialize();
    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

    await conn.dispose();

    expect(conn.isAlive, isFalse);
    expect(transport.isClosed, isTrue);
    // Dispose is idempotent.
    await conn.dispose();
  });

  test('initialize skips authenticate when methodId is null', () async {
    var authenticated = false;
    stubInitialize();
    agent.connection.onRequest('authenticate', (params) {
      authenticated = true;
      return const acpd.AuthenticateResponse().toJson();
    });

    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
    expect(authenticated, isFalse);
  });

  test('initialize sends authenticate when methodId is set', () async {
    String? methodId;
    stubInitialize();
    agent.connection.onRequest('authenticate', (params) {
      methodId = (params! as Map)['methodId'] as String?;
      return const acpd.AuthenticateResponse().toJson();
    });

    await conn.initialize(
      clientName: 'teampilot',
      clientVersion: '1.0.0',
      authenticateMethodId: 'cursor_login',
    );
    expect(methodId, 'cursor_login');
  });

  test('initialize fails when authenticate errors', () async {
    stubInitialize();
    agent.connection.onRequest('authenticate', (params) {
      throw acpd.RpcError(
        code: acpd.ErrorCode.internalError.code,
        message: 'not logged in',
      );
    });

    await expectLater(
      conn.initialize(
        clientName: 'teampilot',
        clientVersion: '1.0.0',
        authenticateMethodId: 'cursor_login',
      ),
      throwsA(isA<AcpAuthenticateException>()),
    );
  });
}

/// Bridges an acpd_test in-memory transport into our byte-pipe [AcpTransport].
///
/// Re-encodes each acpd [acpd.TransportFrame] into an NDJSON byte chunk so the
/// connection under test exercises the same decode path as a real process.
class _PairAcpTransport implements AcpTransport {
  _PairAcpTransport(this._peer);

  final acpd.Transport _peer;
  final _input = StreamController<Uint8List>.broadcast();
  final _stderr = StreamController<List<int>>.broadcast();
  StreamSubscription<acpd.TransportFrame>? _sub;
  bool _closed = false;

  @override
  Stream<Uint8List> get input {
    _sub ??= _peer.incoming.listen(
      (frame) => _input.add(Uint8List.fromList(utf8.encode(frame.toLine()))),
      onDone: _input.close,
    );
    return _input.stream;
  }

  @override
  void write(String frame) {
    var line = frame;
    while (line.endsWith('\n')) {
      line = line.substring(0, line.length - 1);
    }
    if (line.isEmpty) return;
    _peer.send(acpd.TransportFrame.decode(line));
  }

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await _input.close();
    await _stderr.close();
    await _peer.close();
  }

  @override
  bool get isClosed => _closed;
}
