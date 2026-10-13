import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
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
      agentExecutable: capability.agentExecutable,
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

  acpd.RequestPermissionRequest bashPermission(String toolCallId) {
    return acpd.RequestPermissionRequest(
      sessionId: sessionId,
      toolCall: acpd.ToolCallUpdate(
        toolCallId: toolCallId,
        title: 'Run npm install',
      ),
      options: const [
        acpd.PermissionOption(
          optionId: 'allow-1',
          name: 'Yes',
          kind: acpd.PermissionOptionKind.allowOnce,
        ),
        acpd.PermissionOption(
          optionId: 'always-1',
          name: 'Always allow',
          kind: acpd.PermissionOptionKind.allowAlways,
        ),
      ],
    );
  }

  Future<void> driveBashPermission(
    AcpSessionRuntime runtime, {
    required String toolCallId,
    required void Function(acpd.RequestPermissionOutcome? outcome) onOutcome,
  }) async {
    scriptPrompt(() async {
      onOutcome(await agentCtx.requestPermission(bashPermission(toolCallId)));
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });
    await runtime.prompt('go');
    await pumpEventQueue();
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
      expect(envCalls.last, containsPair('GEMINI_CONFIG_DIR', sessionToolDir));
      expect(envCalls.last, containsPair('SURFACE', 'teampilot'));
      expect(envCalls.last, containsPair('PATH', '/usr/bin'));

      // The session was opened on the surviving candidate with cwd set.
      expect(seenNew!.cwd, cwd);
      expect(seenNew!.mcpServers, isEmpty);
      await runtime.close();
    },
  );

  test('start forwards mcpServers to session/new', () async {
    acpd.NewSessionRequest? seenNew;
    agent.connection.onRequest('session/new', (params) {
      seenNew = acpd.NewSessionRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });

    const servers = [
      acpd.McpServerStdio(
        name: 'teammate-bus',
        command: '/bin/bridge',
        args: ['--bus-url', 'http://x'],
      ),
    ];
    final runtime = makeRuntime((argv, env) async => conn);
    await runtime.start(
      tool: CliTool.gemini,
      executable: 'gemini',
      sessionToolDir: sessionToolDir,
      workingDirectory: cwd,
      mcpServers: servers,
    );

    expect(seenNew!.mcpServers, hasLength(1));
    final server = seenNew!.mcpServers.single as acpd.McpServerStdio;
    expect(server.name, 'teammate-bus');
    expect(server.command, '/bin/bridge');
    expect(server.args, ['--bus-url', 'http://x']);
    await runtime.close();
  });

  test(
    'start omits mcpServers when the launch plan says not to forward',
    () async {
      acpd.NewSessionRequest? seenNew;
      agent.connection.onRequest('session/new', (params) {
        seenNew = acpd.NewSessionRequest.fromJson(
          (params! as Map).cast<String, Object?>(),
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      const capability = GeminiAcpCapability();
      final runtime = makeRuntime(
        (argv, env) async => conn,
        launchPlanFor: (_) => AcpLaunchPlan(
          launchArgCandidates: capability.launchArgCandidates,
          buildEnvironment: capability.buildEnvironment,
          agentExecutable: capability.agentExecutable,
          forwardSessionNewMcpServers: false,
        ),
      );
      await runtime.start(
        tool: CliTool.gemini,
        executable: 'gemini',
        sessionToolDir: sessionToolDir,
        workingDirectory: cwd,
        mcpServers: const [
          acpd.McpServerHttp(name: 'teammate-bus', url: 'http://127.0.0.1/mcp'),
        ],
      );

      expect(seenNew!.mcpServers, isEmpty);
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

  AcpLaunchPlan adapterPlan() => AcpLaunchPlan(
    launchArgCandidates: (executable) => [
      [executable],
    ],
    buildEnvironment:
        ({
          required String sessionToolDir,
          required String workingDirectory,
          Map<String, String> baseEnv = const {},
        }) => Map<String, String>.of(baseEnv),
    agentExecutable: (cli) => 'my-adapter',
  );

  test(
    'missing separate adapter binary → AcpLaunchException adapter key',
    () async {
      final runtime = makeRuntime(
        (argv, env) async => throw const ProcessException(
          'my-adapter',
          [],
          'No such file or directory',
          2,
        ),
        launchPlanFor: (_) => adapterPlan(),
      );

      await expectLater(
        startRuntime(runtime),
        throwsA(
          isA<AcpLaunchException>().having(
            (e) => e.reason,
            'reason',
            acpLaunchFailedAdapter,
          ),
        ),
      );
    },
  );

  test(
    'PathNotFoundException for the adapter maps to the adapter key',
    () async {
      final runtime = makeRuntime(
        (argv, env) async => throw const PathNotFoundException(
          'my-adapter',
          OSError('No such file or directory', 2),
        ),
        launchPlanFor: (_) => adapterPlan(),
      );

      await expectLater(
        startRuntime(runtime),
        throwsA(
          isA<AcpLaunchException>().having(
            (e) => e.reason,
            'reason',
            acpLaunchFailedAdapter,
          ),
        ),
      );
    },
  );

  test(
    'missing in-place CLI binary (no adapter) is rethrown unchanged',
    () async {
      final runtime = makeRuntime(
        (argv, env) async => throw const ProcessException(
          'gemini',
          [],
          'No such file or directory',
          2,
        ),
      );

      await expectLater(
        startRuntime(runtime),
        throwsA(isA<ProcessException>()),
      );
    },
  );

  test('start maps CLI executable through plan.agentExecutable', () async {
    final argvCalls = <List<String>>[];
    final plan = AcpLaunchPlan(
      launchArgCandidates: (executable) => [
        [executable, '--acp'],
      ],
      buildEnvironment:
          ({
            required String sessionToolDir,
            required String workingDirectory,
            Map<String, String> baseEnv = const {},
          }) => Map<String, String>.of(baseEnv),
      agentExecutable: (cli) => '$cli-agent',
    );
    final runtime = makeRuntime((argv, env) async {
      argvCalls.add(List.of(argv));
      return conn;
    }, launchPlanFor: (_) => plan);

    await runtime.start(
      tool: CliTool.gemini,
      executable: 'my-cli',
      sessionToolDir: sessionToolDir,
      workingDirectory: cwd,
    );

    expect(argvCalls, [
      ['my-cli-agent', '--acp'],
    ]);
    await runtime.close();
  });

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
    expect(() => runtime.permissionRequests, throwsStateError);
    expect(() => runtime.clientRequests, throwsStateError);
  });

  test('delegates clientRequests after start', () async {
    final runtime = makeRuntime((argv, env) async => conn);
    await startRuntime(runtime);

    expect(runtime.clientRequests, isA<Stream<AcpPendingClientRequest>>());
    await runtime.answerAsk(const AcpAskHoldReply.skipped());
    await runtime.answerPlan(const AcpPlanHoldReply.accepted());
    await runtime.close();
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
            // Reject-only cannot be auto-allowed under default Full access,
            // so a card still surfaces for this runtime delegation check.
            acpd.PermissionOption(
              optionId: 'reject-1',
              name: 'Reject',
              kind: acpd.PermissionOptionKind.rejectOnce,
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
      runtime.answerPermission(AgentPermissionReplyKind.reject);
    });
    await runtime.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(captured, isNotNull);
    expect(captured!.id, 'perm-1');
    expect(outcome, isA<acpd.PermissionCancelled>());
  });

  test(
    'default Full access auto-allows bash without a card and prefers allow-always',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      final runtime = makeRuntime((argv, env) async => conn);
      await startRuntime(runtime);

      final cards = <AgentPermissionRequest>[];
      final permissionSub = runtime.permissionRequests.listen(cards.add);
      await driveBashPermission(
        runtime,
        toolCallId: 'perm-fa',
        onOutcome: (value) => outcome = value,
      );
      permissionSub.cancel();

      expect(cards, isEmpty);
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
      await runtime.close();
    },
  );

  test(
    'start with permissionPolicy fullAccess auto-allows bash without a card',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      final runtime = makeRuntime((argv, env) async => conn);
      await runtime.start(
        tool: CliTool.gemini,
        executable: 'gemini',
        sessionToolDir: sessionToolDir,
        workingDirectory: cwd,
        baseEnv: const {'PATH': '/usr/bin'},
        permissionPolicy: LaunchSecurityPolicy.fullAccess,
      );

      final cards = <AgentPermissionRequest>[];
      final permissionSub = runtime.permissionRequests.listen(cards.add);
      await driveBashPermission(
        runtime,
        toolCallId: 'perm-fa-explicit',
        onOutcome: (value) => outcome = value,
      );
      permissionSub.cancel();

      expect(cards, isEmpty);
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
      await runtime.close();
    },
  );

  test('start with permissionPolicy Ask surfaces a bash permission card', () async {
    acpd.RequestPermissionOutcome? outcome;
    final runtime = makeRuntime((argv, env) async => conn);
    await runtime.start(
      tool: CliTool.gemini,
      executable: 'gemini',
      sessionToolDir: sessionToolDir,
      workingDirectory: cwd,
      baseEnv: const {'PATH': '/usr/bin'},
      permissionPolicy: LaunchSecurityPolicy.ask,
    );

    final cards = <AgentPermissionRequest>[];
    final permissionSub = runtime.permissionRequests.listen((request) {
      cards.add(request);
      runtime.answerPermission(AgentPermissionReplyKind.allowOnce);
    });
    await driveBashPermission(
      runtime,
      toolCallId: 'perm-ask',
      onOutcome: (value) => outcome = value,
    );
    permissionSub.cancel();

    expect(cards, hasLength(1));
    expect(cards.single.id, 'perm-ask');
    expect(outcome, isA<acpd.PermissionSelected>());
    expect((outcome! as acpd.PermissionSelected).optionId, 'allow-1');
    await runtime.close();
  });

  test(
    'setPermissionPolicy(Ask) after start surfaces the next bash request',
    () async {
      acpd.RequestPermissionOutcome? first;
      acpd.RequestPermissionOutcome? second;
      final runtime = makeRuntime((argv, env) async => conn);
      await startRuntime(runtime);

      final cards = <AgentPermissionRequest>[];
      final permissionSub = runtime.permissionRequests.listen((request) {
        cards.add(request);
        runtime.answerPermission(AgentPermissionReplyKind.allowOnce);
      });

      await driveBashPermission(
        runtime,
        toolCallId: 'perm-before',
        onOutcome: (value) => first = value,
      );
      expect(cards, isEmpty);
      expect(first, isA<acpd.PermissionSelected>());
      expect((first! as acpd.PermissionSelected).optionId, 'always-1');

      runtime.setPermissionPolicy(LaunchSecurityPolicy.ask);

      await driveBashPermission(
        runtime,
        toolCallId: 'perm-after',
        onOutcome: (value) => second = value,
      );
      permissionSub.cancel();

      expect(cards, hasLength(1));
      expect(cards.single.id, 'perm-after');
      expect(second, isA<acpd.PermissionSelected>());
      expect((second! as acpd.PermissionSelected).optionId, 'allow-1');
      await runtime.close();
    },
  );

  test(
    'setPermissionPolicy(Ask) during session/new surfaces a bash card',
    () async {
      final gate = Completer<void>();
      agent.connection.onRequest('session/new', (params) async {
        await gate.future;
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      final runtime = makeRuntime((argv, env) async => conn);
      final started = runtime.start(
        tool: CliTool.gemini,
        executable: 'gemini',
        sessionToolDir: sessionToolDir,
        workingDirectory: cwd,
        baseEnv: const {'PATH': '/usr/bin'},
      );
      await pumpEventQueue();
      runtime.setPermissionPolicy(LaunchSecurityPolicy.ask);
      gate.complete();
      await started;

      acpd.RequestPermissionOutcome? outcome;
      final cards = <AgentPermissionRequest>[];
      final permissionSub = runtime.permissionRequests.listen((request) {
        cards.add(request);
        runtime.answerPermission(AgentPermissionReplyKind.allowOnce);
      });
      await driveBashPermission(
        runtime,
        toolCallId: 'perm-during-new',
        onOutcome: (value) => outcome = value,
      );
      permissionSub.cancel();

      expect(cards, hasLength(1));
      expect(cards.single.id, 'perm-during-new');
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'allow-1');
      await runtime.close();
    },
  );

  test(
    'setPermissionPolicy(Ask) before start is not clobbered by fullAccess arg',
    () async {
      final runtime = makeRuntime((argv, env) async => conn);
      runtime.setPermissionPolicy(LaunchSecurityPolicy.ask);
      await runtime.start(
        tool: CliTool.gemini,
        executable: 'gemini',
        sessionToolDir: sessionToolDir,
        workingDirectory: cwd,
        baseEnv: const {'PATH': '/usr/bin'},
        permissionPolicy: LaunchSecurityPolicy.fullAccess,
      );

      acpd.RequestPermissionOutcome? outcome;
      final cards = <AgentPermissionRequest>[];
      final permissionSub = runtime.permissionRequests.listen((request) {
        cards.add(request);
        runtime.answerPermission(AgentPermissionReplyKind.allowOnce);
      });
      await driveBashPermission(
        runtime,
        toolCallId: 'perm-before-start',
        onOutcome: (value) => outcome = value,
      );
      permissionSub.cancel();

      expect(cards, hasLength(1));
      expect(cards.single.id, 'perm-before-start');
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'allow-1');
      await runtime.close();
    },
  );

  test('cancel before start does not throw', () {
    final runtime = makeRuntime((argv, env) async => conn);
    expect(() => runtime.cancel(), returnsNormally);
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
