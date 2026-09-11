import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/acp/acp_connection.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/acp/acp_transport.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  const sessionId = 'sess-1';
  const cwd = '/tmp/workspace';
  const sessionToolDir = '/tmp/session-tools';

  late acpd_test.MockAgent agent;
  late acpd.AgentContext agentCtx;
  late _PairAcpTransport transport;
  late AcpAgentConnection conn;

  setUp(() async {
    agent = acpd_test.MockAgent();
    agentCtx = acpd.AgentContext(agent.connection);
    transport = _PairAcpTransport(agent.clientTransport);
    conn = AcpAgentConnection(
      transport: transport,
      logger: AcpFrameLogger(enableDiskLog: false),
      translator: const GeminiAcpTranslator(),
    );
    agent.connection.onRequest('initialize', (params) {
      return acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
      ).toJson();
    });
    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });
  });

  tearDown(() async {
    await conn.dispose();
    await agent.close();
  });

  /// Wraps the Gemini capability into an [AcpLaunchPlan] for the resolver.
  AcpLaunchPlan geminiPlan() {
    const capability = GeminiAcpCapability();
    return AcpLaunchPlan(
      launchArgCandidates: capability.launchArgCandidates,
      buildEnvironment: capability.buildEnvironment,
    );
  }

  AcpSessionRuntime makeRuntime(
    AcpConnectionSpawner spawner, {
    AcpLaunchPlanResolver? launchPlanFor,
  }) {
    return AcpSessionRuntime(
      spawner: spawner,
      logger: AcpFrameLogger(enableDiskLog: false),
      launchPlanFor: launchPlanFor ?? (_) => geminiPlan(),
    );
  }

  Future<void> startRuntime(AcpSessionRuntime runtime) {
    return runtime.start(
      tool: CliTool.gemini,
      executable: 'gemini',
      sessionToolDir: sessionToolDir,
      workingDirectory: cwd,
      baseEnv: const {'PATH': '/usr/bin'},
    );
  }

  /// Scripts the agent's `session/prompt` handler.
  void scriptPrompt(FutureOr<Object?> Function() body) {
    agent.connection.onRequest('session/prompt', (params) => body());
  }

  acpd.AgentMessageChunk message(String text) => acpd.AgentMessageChunk(
    chunk: acpd.ContentChunk(content: acpd.TextContentBlock(text: text)),
  );

  test(
    'start probes candidates in order and falls back after rejection',
    () async {
      acpd.NewSessionRequest? seenNew;
      agent.connection.onRequest('session/new', (params) {
        seenNew = acpd.NewSessionRequest.fromJson(
          (params! as Map).cast<String, Object?>(),
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      final argvCalls = <List<String>>[];
      final envCalls = <Map<String, String>>[];
      final runtime = makeRuntime((argv, env) async {
        argvCalls.add(List.of(argv));
        envCalls.add(env);
        if (argv.last == '--acp') {
          // gemini rejecting the old flag name: process exits before the
          // handshake completes.
          throw AcpFlagRejected('agent exited before handshake (--acp)');
        }
        return conn;
      });

      await startRuntime(runtime);

      expect(argvCalls, [
        ['gemini', '--acp'],
        ['gemini', '--experimental-acp'],
      ]);
      // The capability-built environment reached the spawner.
      expect(
        envCalls.last,
        containsPair('GEMINI_CONFIG_DIR', '$sessionToolDir/gemini'),
      );
      expect(envCalls.last, containsPair('SURFACE', 'teampilot'));
      expect(envCalls.last, containsPair('PATH', '/usr/bin'));

      // The session was opened on the surviving candidate with cwd set.
      expect(seenNew!.cwd, cwd);
      await runtime.close();
    },
  );

  test(
    'all candidates rejected → AcpLaunchException carrying the version key',
    () async {
      var attempts = 0;
      final runtime = makeRuntime((argv, env) async {
        attempts++;
        throw AcpFlagRejected('agent exited before handshake');
      });

      await expectLater(
        startRuntime(runtime),
        throwsA(
          isA<AcpLaunchException>().having(
            (e) => e.reason,
            'reason',
            acpLaunchFailedVersion,
          ),
        ),
      );
      expect(attempts, 2);
    },
  );

  test(
    'non-flag spawner errors are rethrown, not treated as rejections',
    () async {
      final runtime = makeRuntime((argv, env) async {
        throw StateError('spawn exploded');
      });

      await expectLater(startRuntime(runtime), throwsStateError);
    },
  );

  test('a tool without an ACP capability fails with a clear error', () async {
    final runtime = makeRuntime(
      (argv, env) async => conn,
      launchPlanFor: (_) => null,
    );

    await expectLater(startRuntime(runtime), throwsArgumentError);
  });

  test('a second start before close is refused', () async {
    final runtime = makeRuntime((argv, env) async => conn);
    await startRuntime(runtime);

    await expectLater(startRuntime(runtime), throwsStateError);

    await runtime.close();
  });

  test('session streams throw before start completes', () async {
    final runtime = makeRuntime((argv, env) async => conn);

    expect(() => runtime.updates, throwsStateError);
  });

  test('delegates prompt and updates to the session', () async {
    scriptPrompt(() {
      agentCtx.sessionUpdate(sessionId: sessionId, update: message('Hello'));
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    final runtime = makeRuntime((argv, env) async => conn);
    await startRuntime(runtime);

    final events = <AcpSessionUpdate>[];
    final sub = runtime.updates.listen(events.add);
    await runtime.prompt('hi');
    await pumpEventQueue();
    sub.cancel();

    expect(events, [
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
      const AcpStop(kind: AcpStopKind.endTurn),
    ]);
  });

  test('delegates permission requests and answers to the session', () async {
    acpd.RequestPermissionOutcome? outcome;
    scriptPrompt(() async {
      outcome = await agentCtx.requestPermission(
        acpd.RequestPermissionRequest(
          sessionId: sessionId,
          toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-1'),
          options: const [
            acpd.PermissionOption(
              optionId: 'allow-1',
              name: 'Yes',
              kind: acpd.PermissionOptionKind.allowOnce,
            ),
          ],
        ),
      );
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    final runtime = makeRuntime((argv, env) async => conn);
    await startRuntime(runtime);

    AgentPermissionRequest? captured;
    final permissionSub = runtime.permissionRequests.listen((request) {
      captured = request;
      runtime.answerPermission(AgentPermissionReplyKind.allowOnce);
    });
    await runtime.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(captured, isNotNull);
    expect(captured!.id, 'perm-1');
    expect(outcome, isA<acpd.PermissionSelected>());
  });

  test('delegates cancel; close disposes the connection', () async {
    final cancelReceived = Completer<void>();
    agent.connection.onNotification('session/cancel', (params) {
      if (!cancelReceived.isCompleted) cancelReceived.complete();
    });
    scriptPrompt(() async {
      await cancelReceived.future;
      return acpd.PromptResponse(
        stopReason: acpd.StopReason.cancelled,
      ).toJson();
    });

    final runtime = makeRuntime((argv, env) async => conn);
    await startRuntime(runtime);

    final events = <AcpSessionUpdate>[];
    final sub = runtime.updates.listen(events.add);
    final promptDone = runtime.prompt('go');
    await pumpEventQueue();
    runtime.cancel();
    await promptDone;
    await pumpEventQueue();
    sub.cancel();

    expect(events, [const AcpStop(kind: AcpStopKind.cancelled)]);

    await runtime.close();
    expect(conn.isAlive, isFalse);
  });
}

/// Bridges an acpd_test in-memory transport into our byte-pipe [AcpTransport].
///
/// Re-encodes each acpd [acpd.TransportFrame] into an NDJSON byte chunk so the
/// connection under test exercises the same decode path as a real process
/// (same bridge as `acp_session_test.dart`).
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
