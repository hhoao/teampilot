import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_connection.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_transport.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/cli/cursor/capabilities/acp.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  const sessionId = 'sess-1';
  const cwd = '/tmp/workspace';

  late acpd_test.MockAgent agent;
  late acpd.AgentContext agentCtx;
  late _PairAcpTransport transport;
  late AcpAgentConnection conn;
  late AcpAgentSession session;

  setUp(() async {
    agent = acpd_test.MockAgent();
    agentCtx = acpd.AgentContext(agent.connection);
    transport = _PairAcpTransport(agent.clientTransport);
    conn = AcpAgentConnection(
      transport: transport,
      logger: AcpFrameLogger(mirrorToLog: false),
      translator: const GeminiAcpTranslator(),
    );
    agent.connection.onRequest('initialize', (params) {
      return acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
        // History reconciliation replays via `session/load`; advertise it so
        // the capability guard in loadHistory passes.
        agentCapabilities: const acpd.AgentCapabilities(loadSession: true),
      ).toJson();
    });
    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });
  });

  tearDown(() async {
    session.dispose();
    await conn.dispose();
    await agent.close();
  });

  /// Opens a session through the connection under test.
  Future<AcpAgentSession> openSession({Duration? permissionTimeout}) async {
    session = await conn.openSession(
      cwd: cwd,
      permissionTimeout:
          permissionTimeout ?? AcpAgentSession.defaultPermissionTimeout,
    );
    return session;
  }

  /// Replaces the Gemini connection from [setUp] with [translator].
  ///
  /// Cursor tests must construct [AcpAgentConnection] with
  /// [CursorAcpTranslator]; disposing the previous connection closes the
  /// paired transport, so the mock agent is rebuilt too.
  Future<void> rebuildConnection(AcpAgentTranslator translator) async {
    await conn.dispose();
    await agent.close();
    agent = acpd_test.MockAgent();
    agentCtx = acpd.AgentContext(agent.connection);
    transport = _PairAcpTransport(agent.clientTransport);
    conn = AcpAgentConnection(
      transport: transport,
      logger: AcpFrameLogger(mirrorToLog: false),
      translator: translator,
    );
    agent.connection.onRequest('initialize', (params) {
      return acpd.InitializeResponse(
        protocolVersion: acpd.ProtocolVersion.v1,
        // History reconciliation replays via `session/load`; advertise it so
        // the capability guard in loadHistory passes.
        agentCapabilities: const acpd.AgentCapabilities(loadSession: true),
      ).toJson();
    });
    await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });
  }

  /// Scripts the agent's `session/prompt` handler.
  void scriptPrompt(FutureOr<Object?> Function() body) {
    agent.connection.onRequest('session/prompt', (params) => body());
  }

  /// Asks the client to approve [request] and decodes the reply.
  ///
  /// Stands in for `AgentContext.requestPermission`, which parses acpd's flat
  /// response shape. ACP actually nests the outcome
  /// (`{outcome: {outcome, optionId}}`), and that is the only shape a real
  /// agent (`claude-agent-acp`, Gemini, Cursor) accepts.
  Future<acpd.RequestPermissionOutcome> requestPermission(
    acpd.RequestPermissionRequest request,
  ) async {
    final raw = await agent.connection.sendRequest(
      'session/request_permission',
      params: request.toJson(),
      mapResult: (r) => r,
    );
    final response = Map<String, Object?>.from(raw! as Map);
    final outcome = response['outcome'];
    if (outcome is! Map) {
      fail('permission outcome is not nested: $response');
    }
    return acpd.RequestPermissionOutcome.fromJson(
      Map<String, Object?>.from(outcome),
    );
  }

  acpd.AgentMessageChunk message(String text) => acpd.AgentMessageChunk(
    chunk: acpd.ContentChunk(content: acpd.TextContentBlock(text: text)),
  );

  test('parseAcpAuthNotice reads Claude adapter payloads', () async {
    session = await openSession();
    expect(
      parseAcpAuthNotice({
        'kind': 'none',
        'message': 'Not logged in',
      }, method: '_auth/status_update'),
      const AcpAuthNotice(loggedIn: false, message: 'Not logged in'),
    );
    expect(
      parseAcpAuthNotice({
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': '_auth/status_update',
          'status': {'kind': 'none', 'message': 'Not logged in'},
        },
      }),
      const AcpAuthNotice(loggedIn: false, message: 'Not logged in'),
    );
    expect(
      parseAcpAuthNotice({
        'authStatus': {'kind': 'none', 'label': 'Not logged in'},
      }, method: '_auth/status_update'),
      const AcpAuthNotice(loggedIn: false, message: 'Not logged in'),
    );
    expect(
      parseAcpAuthNotice({
        'authStatus': {
          'kind': 'account',
          'label': 'Claude Pro',
          'account': {'email': 'a@b.c'},
        },
      }, method: '_auth/status_update'),
      const AcpAuthNotice(loggedIn: true, message: 'Claude Pro'),
    );
  });

  test(
    '_auth/status_update during session/new is kept on the connection',
    () async {
      agent.connection.onRequest('session/new', (params) {
        agent.connection.notify(
          '_auth/status_update',
          params: {'kind': 'none', 'message': 'Not logged in'},
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      await openSession();
      expect(
        conn.lastAuthNotice,
        const AcpAuthNotice(loggedIn: false, message: 'Not logged in'),
      );
    },
  );

  test(
    'a second openSession on the same connection throws StateError',
    () async {
      await openSession();

      // A second session would steal the first's request_permission handler
      // (acpd's onRequest replaces), so the connection refuses it.
      await expectLater(conn.openSession(cwd: cwd), throwsStateError);
    },
  );

  test(
    'openSession works again after the previous session is disposed',
    () async {
      final first = await openSession();
      first.dispose();

      session = await conn.openSession(cwd: cwd);
      expect(session.sessionId, sessionId);
    },
  );

  test('a second prompt while one is in flight throws StateError', () async {
    final resume = Completer<void>();
    scriptPrompt(() async {
      await resume.future;
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    await openSession();

    final first = session.prompt('one');
    await pumpEventQueue();
    await expectLater(session.prompt('two'), throwsStateError);

    resume.complete();
    await first;
  });

  test('tool_call background flag is mapped from rawInput', () async {
    session = await openSession();
    final update = session.updates.first;
    agent.connection.notify(
      'session/update',
      params: {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-bg',
          'title': 'dart run tool/run_tests.dart',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {
            'command': 'dart run tool/run_tests.dart',
            'background': true,
          },
        },
      },
    );

    expect(
      await update,
      const AcpToolCallUpdate(
        toolCallId: 'call-bg',
        title: 'dart run tool/run_tests.dart',
        status: AcpToolCallStatus.pending,
        background: true,
      ),
    );
  });

  test('loadHistory replays the session without emitting live updates', () async {
    session = await openSession();
    final emitted = <AcpSessionUpdate>[];
    final sub = session.updates.listen(emitted.add);
    agent.connection.onRequest('session/load', (params) {
      agent.connection.notify(
        'session/update',
        params: {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'replayed'},
          },
        },
      );
      return acpd.LoadSessionResponse().toJson();
    });

    final history = await session.loadHistory();

    expect(history, const [
      AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'replayed',
        isThought: false,
      ),
    ]);
    await pumpEventQueue();
    expect(emitted, isEmpty);
    await sub.cancel();
  });

  test(
    'loadHistory collects past bootstrap suppression on a loaded session',
    () async {
      agent.connection.onRequest(
        'session/load',
        (params) => acpd.LoadSessionResponse().toJson(),
      );
      session = await conn.loadSession(sessionId: sessionId, cwd: cwd);

      final emitted = <AcpSessionUpdate>[];
      final sub = session.updates.listen(emitted.add);
      agent.connection.notify(
        'session/update',
        params: {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'bootstrap'},
          },
        },
      );
      await pumpEventQueue();
      expect(emitted, isEmpty, reason: 'load/resume replay stays suppressed');

      agent.connection.onRequest('session/load', (params) {
        agent.connection.notify(
          'session/update',
          params: {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'reconciled'},
            },
          },
        );
        return acpd.LoadSessionResponse().toJson();
      });
      final history = await session.loadHistory();
      expect(
        history,
        const [
          AcpMessageChunk(
            role: AcpRole.assistant,
            content: 'reconciled',
            isThought: false,
          ),
        ],
      );
      expect(emitted, isEmpty, reason: 'reconciliation never leaks live');
      await sub.cancel();
    },
  );

  test('loadHistory is empty when the agent does not negotiate load', () async {
    // Rebuild a connection whose initialize omits `loadSession`.
    await conn.dispose();
    await agent.close();
    agent = acpd_test.MockAgent();
    agentCtx = acpd.AgentContext(agent.connection);
    transport = _PairAcpTransport(agent.clientTransport);
    conn = AcpAgentConnection(
      transport: transport,
      logger: AcpFrameLogger(mirrorToLog: false),
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
    session = await openSession();

    expect(await session.loadHistory(), isEmpty);
  });

  test(
    'permission request racing dispose answers cancelled without throwing',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-d'),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-d',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      // Disposing mid-hold (card dismissed / teardown racing the request)
      // must answer the agent with the cancelled default, not throw on the
      // closed controller.
      final permissionSub = session.permissionRequests.listen((request) {
        session.dispose();
      });
      await session.prompt('go');
      await pumpEventQueue();
      permissionSub.cancel();

      expect(outcome, isA<acpd.PermissionCancelled>());

      // Disposing also released the connection's open-session slot.
      session = await conn.openSession(cwd: cwd);
      expect(session.sessionId, sessionId);
    },
  );

  test('prompt maps message chunks and the end_turn stop in order', () async {
    acpd.NewSessionRequest? seenNew;
    agent.connection.onRequest('session/new', (params) {
      seenNew = acpd.NewSessionRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });
    scriptPrompt(() {
      agentCtx.sessionUpdate(sessionId: sessionId, update: message('Hello'));
      agentCtx.sessionUpdate(sessionId: sessionId, update: message(' world'));
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    await openSession();

    expect(seenNew!.cwd, cwd);
    expect(seenNew!.mcpServers, isEmpty);

    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);
    await session.prompt('hi');
    await pumpEventQueue();
    sub.cancel();

    expect(events, [
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: ' world',
        isThought: false,
      ),
      const AcpStop(kind: AcpStopKind.endTurn),
    ]);
  });

  test('a load session drops replayed updates until the first prompt',
      () async {
    agent.connection.onRequest('session/load', (params) {
      return acpd.LoadSessionResponse().toJson();
    });
    session = await conn.loadSession(sessionId: 'agent-9', cwd: cwd);

    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);

    // session/load makes the agent replay its whole history; the app
    // transcript is the UI source of truth, so none of it may reach the
    // stream (this is the whole point of suppressBootstrapUpdates).
    agentCtx.sessionUpdate(sessionId: 'agent-9', update: message('replayed'));
    await pumpEventQueue();
    expect(events, isEmpty);

    // The first prompt releases the hold.
    scriptPrompt(() {
      agentCtx.sessionUpdate(sessionId: 'agent-9', update: message('fresh'));
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });
    await session.prompt('hi');
    await pumpEventQueue();
    sub.cancel();

    expect(events, [
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'fresh',
        isThought: false,
      ),
      const AcpStop(kind: AcpStopKind.endTurn),
    ]);
  });

  test('openSession records mcpServers on session/new', () async {
    acpd.NewSessionRequest? seenNew;
    agent.connection.onRequest('session/new', (params) {
      seenNew = acpd.NewSessionRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });

    session = await conn.openSession(
      cwd: cwd,
      mcpServers: const [
        acpd.McpServerStdio(
          name: 'teammate-bus',
          command: '/bin/bridge',
          args: ['--bus-url', 'http://x'],
        ),
      ],
    );

    expect(seenNew!.mcpServers, hasLength(1));
    final server = seenNew!.mcpServers.single as acpd.McpServerStdio;
    expect(server.name, 'teammate-bus');
    expect(server.command, '/bin/bridge');
    expect(server.args, ['--bus-url', 'http://x']);
  });

  test('openSession records _meta on session/new', () async {
    acpd.NewSessionRequest? seenNew;
    agent.connection.onRequest('session/new', (params) {
      seenNew = acpd.NewSessionRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return acpd.NewSessionResponse(sessionId: sessionId).toJson();
    });

    session = await conn.openSession(
      cwd: cwd,
      meta: const {
        'claudeCode': {
          'options': {
            'disallowedTools': ['ListAgents'],
          },
        },
      },
    );

    expect(seenNew!.meta['claudeCode'], {
      'options': {
        'disallowedTools': ['ListAgents'],
      },
    });
  });

  test('exposes the agent model config option from session/new', () async {
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(
        sessionId: sessionId,
        configOptions: [_modelOption('sonnet')],
      ).toJson();
    });

    await openSession();

    final state = session.modelState;
    expect(state, isNotNull);
    expect(state!.configId, 'model');
    expect(state.currentId, 'sonnet');
    expect(state.options.map((option) => option.id), ['sonnet', 'opus']);
  });

  test('setModel sends session/set_config_option and adopts the response',
      () async {
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(
        sessionId: sessionId,
        configOptions: [_modelOption('sonnet')],
      ).toJson();
    });
    acpd.SetSessionConfigOptionRequest? seen;
    agent.connection.onRequest('session/set_config_option', (params) {
      seen = acpd.SetSessionConfigOptionRequest.fromJson(
        (params! as Map).cast<String, Object?>(),
      );
      return acpd.SetSessionConfigOptionResponse(
        configOptions: [_modelOption('opus')],
      ).toJson();
    });

    await openSession();
    await session.setModel('opus');

    expect(seen, isA<acpd.SetValueIdConfigOption>());
    expect(seen!.sessionId, sessionId);
    expect(seen!.configId, 'model');
    expect((seen! as acpd.SetValueIdConfigOption).value, 'opus');
    expect(session.modelState!.currentId, 'opus');
  });

  test('rejects a model the agent did not advertise', () async {
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(
        sessionId: sessionId,
        configOptions: [_modelOption('sonnet')],
      ).toJson();
    });
    await openSession();

    await expectLater(session.setModel('unknown'), throwsArgumentError);
  });

  test('config option updates refresh modelState and emit an update', () async {
    agent.connection.onRequest('session/new', (params) {
      return acpd.NewSessionResponse(
        sessionId: sessionId,
        configOptions: [_modelOption('sonnet')],
      ).toJson();
    });
    await openSession();
    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);

    agentCtx.sessionUpdate(
      sessionId: sessionId,
      update: acpd.ConfigOptionSessionUpdate(
        configOptions: [_modelOption('opus')],
      ),
    );
    await pumpEventQueue();
    sub.cancel();

    expect(session.modelState!.currentId, 'opus');
    final update = events.whereType<AcpModelStateUpdate>().single;
    expect(update.state!.currentId, 'opus');
    expect(
      update.state!.options.map((option) => option.id),
      ['sonnet', 'opus'],
    );
  });

  test('maps thought, tool call, and plan updates', () async {
    scriptPrompt(() {
      agentCtx.sessionUpdate(
        sessionId: sessionId,
        update: acpd.AgentThoughtChunk(
          chunk: acpd.ContentChunk(content: acpd.TextContentBlock(text: 'hm')),
        ),
      );
      agentCtx.sessionUpdate(
        sessionId: sessionId,
        update: acpd.ToolCallUpdateSession(
          toolCall: acpd.ToolCall(
            toolCallId: 'tc1',
            title: 'Run tests',
            kind: acpd.ToolKind.execute,
            status: acpd.ToolCallStatus.inProgress,
          ),
        ),
      );
      agentCtx.sessionUpdate(
        sessionId: sessionId,
        update: acpd.ToolCallStatusUpdate(
          update: acpd.ToolCallUpdate(
            toolCallId: 'tc1',
            status: acpd.ToolCallStatus.completed,
          ),
        ),
      );
      agentCtx.sessionUpdate(
        sessionId: sessionId,
        update: acpd.PlanUpdate(
          plan: acpd.Plan(
            entries: [
              acpd.PlanEntry(
                content: 'Do it',
                priority: acpd.PlanEntryPriority.high,
                status: acpd.PlanEntryStatus.pending,
              ),
            ],
          ),
        ),
      );
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    await openSession();

    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);
    await session.prompt('go');
    await pumpEventQueue();
    sub.cancel();

    expect(events, [
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'hm',
        isThought: true,
      ),
      const AcpToolCallUpdate(
        toolCallId: 'tc1',
        title: 'Run tests',
        status: AcpToolCallStatus.inProgress,
      ),
      const AcpToolCallUpdate(
        toolCallId: 'tc1',
        status: AcpToolCallStatus.completed,
      ),
      const AcpPlan(
        entries: [
          AcpPlanEntry(
            content: 'Do it',
            priority: AcpPlanEntryPriority.high,
            status: AcpPlanEntryStatus.pending,
          ),
        ],
      ),
      const AcpStop(kind: AcpStopKind.endTurn),
    ]);
  });

  test(
    'teammate-bus permission during session/new is auto-allowed',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      agent.connection.onRequest('session/new', (params) async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-early',
              title: 'teammate-bus-read_messages: read_messages',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-1',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
              acpd.PermissionOption(
                optionId: 'allow-1',
                name: 'Allow once',
                kind: acpd.PermissionOptionKind.allowOnce,
              ),
              acpd.PermissionOption(
                optionId: 'always-1',
                name: 'Allow always',
                kind: acpd.PermissionOptionKind.allowAlways,
              ),
            ],
          ),
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      await openSession();

      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
    },
  );

  test(
    'Claude MCP teammate-bus permission during session/new is auto-allowed',
    () async {
      Object? result;
      agent.connection.onRequest('session/new', (params) async {
        result = await agent.connection.sendRequest(
          'session/request_permission',
          params: {
            'sessionId': sessionId,
            'toolCall': {
              'toolCallId': 'perm-mcp',
              'title': 'Use MCP tool',
              '_meta': {
                'claudeCode': {
                  'mcpServer': {'name': 'teammate-bus', 'source': 'sdk'},
                  'toolName': 'mcp__teammate-bus__list_teammates',
                },
              },
            },
            'options': [
              {
                'optionId': 'reject-1',
                'name': 'Reject',
                'kind': 'reject_once',
              },
              {'optionId': 'yes-1', 'name': 'Yes', 'kind': 'selected'},
            ],
          },
          mapResult: (r) => r,
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      await openSession();

      expect(result, isA<Map>());
      final map = Map<String, Object?>.from(result! as Map);
      expect(map['outcome'], {'outcome': 'selected', 'optionId': 'yes-1'});
    },
  );

  test(
    'teammate-bus permission after open is auto-allowed without a card',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-bus',
              title: 'list_teammates',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'allow-1',
                name: 'Allow once',
                kind: acpd.PermissionOptionKind.allowOnce,
              ),
              acpd.PermissionOption(
                optionId: 'always-1',
                name: 'Allow always',
                kind: acpd.PermissionOptionKind.allowAlways,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
      });
      await session.prompt('go');
      permissionSub.cancel();

      expect(captured, isNull);
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
    },
  );

  test(
    'fullAccess auto-allows bash-style permission without a card',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-bash',
              title: 'Run `npm install`',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'allow-1',
                name: 'Allow once',
                kind: acpd.PermissionOptionKind.allowOnce,
              ),
              acpd.PermissionOption(
                optionId: 'always-1',
                name: 'Allow always',
                kind: acpd.PermissionOptionKind.allowAlways,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
      });
      await session.prompt('go');
      permissionSub.cancel();

      expect(captured, isNull);
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
    },
  );

  test(
    'hyphenated Cursor permission kinds auto-allow without a card',
    () async {
      Object? result;
      scriptPrompt(() async {
        result = await agent.connection.sendRequest(
          'session/request_permission',
          params: {
            'sessionId': sessionId,
            'toolCall': {
              'toolCallId': 'perm-hyphen',
              'title': 'teammate-bus-read_messages: read_messages',
            },
            'options': [
              {
                'optionId': 'allow-once',
                'name': 'Allow once',
                'kind': 'allow-once',
              },
              {
                'optionId': 'allow-always',
                'name': 'Allow always',
                'kind': 'allow-always',
              },
              {
                'optionId': 'reject-once',
                'name': 'Reject',
                'kind': 'reject-once',
              },
            ],
          },
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession(
        permissionTimeout: const Duration(milliseconds: 200),
      );
      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
      });
      await session.prompt('go');
      permissionSub.cancel();

      expect(captured, isNull);
      expect(result, {
        'outcome': {'outcome': 'selected', 'optionId': 'allow-always'},
      });
    },
  );

  test(
    'Cursor auto-allow nests permission selected for hyphenated kinds',
    () async {
      await rebuildConnection(const CursorAcpTranslator());

      Object? result;
      scriptPrompt(() async {
        result = await agent.connection.sendRequest(
          'session/request_permission',
          params: {
            'sessionId': sessionId,
            'toolCall': {
              'toolCallId': 'perm-cursor',
              'title': 'teammate-bus-read_messages: read_messages',
            },
            'options': [
              {
                'optionId': 'allow-once',
                'name': 'Allow once',
                'kind': 'allow-once',
              },
              {
                'optionId': 'allow-always',
                'name': 'Allow always',
                'kind': 'allow-always',
              },
            ],
          },
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession(
        permissionTimeout: const Duration(milliseconds: 200),
      );
      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
      });
      await session.prompt('go');
      permissionSub.cancel();

      expect(captured, isNull);
      expect(result, {
        'outcome': {
          'outcome': 'selected',
          'optionId': 'allow-always',
        },
      });
    },
  );

  test(
    'reject-only permission still surfaces a card',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-1',
              title: 'Run `npm install`',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-1',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
            ],
          ),
        );
        agentCtx.sessionUpdate(sessionId: sessionId, update: message('done'));
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
        session.answerPermission(AgentPermissionReplyKind.reject);
      });
      final events = <AcpSessionUpdate>[];
      final sub = session.updates.listen(events.add);
      await session.prompt('go');
      await pumpEventQueue();
      sub.cancel();
      permissionSub.cancel();

      expect(captured, isNotNull);
      expect(captured!.id, 'perm-1');
      expect(captured!.description, 'Run `npm install`');
      expect(captured!.sessionID, sessionId);
      expect(captured!.toolCallID, 'perm-1');
      expect(captured!.always, isEmpty);

      expect(outcome, isA<acpd.PermissionCancelled>());

      expect(events, [
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'done',
          isThought: false,
        ),
        const AcpStop(kind: AcpStopKind.endTurn),
      ]);
    },
  );

  test(
    'always echoes the optionId payload; reject maps to cancelled',
    () async {
      acpd.RequestPermissionOutcome? firstOutcome;
      acpd.RequestPermissionOutcome? secondOutcome;
      var promptCount = 0;
      agent.connection.onRequest('session/prompt', (params) async {
        if (promptCount++ == 0) {
          firstOutcome = await requestPermission(
            acpd.RequestPermissionRequest(
              sessionId: sessionId,
              toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-a'),
              options: const [
                acpd.PermissionOption(
                  optionId: 'allow-a',
                  name: 'Yes',
                  kind: acpd.PermissionOptionKind.allowOnce,
                ),
                acpd.PermissionOption(
                  optionId: 'always-a',
                  name: 'Always allow',
                  kind: acpd.PermissionOptionKind.allowAlways,
                ),
              ],
            ),
          );
        } else {
          secondOutcome = await requestPermission(
            acpd.RequestPermissionRequest(
              sessionId: sessionId,
              toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-b'),
              options: const [
                acpd.PermissionOption(
                  optionId: 'reject-b',
                  name: 'Reject',
                  kind: acpd.PermissionOptionKind.rejectOnce,
                ),
              ],
            ),
          );
        }
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      final answers = <AgentPermissionRequest>[];
      final permissionSub = session.permissionRequests.listen((request) {
        answers.add(request);
        if (request.id == 'perm-a') {
          session.answerPermission(
            AgentPermissionReplyKind.always,
            always: const AgentPermissionAlwaysOption(
              label: 'Always allow',
              payload: 'always-a',
            ),
          );
        } else {
          session.answerPermission(AgentPermissionReplyKind.reject);
        }
      });

      await session.prompt('one');
      await session.prompt('two');
      permissionSub.cancel();

      expect(firstOutcome, isA<acpd.PermissionSelected>());
      expect((firstOutcome! as acpd.PermissionSelected).optionId, 'always-a');
      expect(secondOutcome, isA<acpd.PermissionCancelled>());
    },
  );

  test(
    'cancel keeps accepting trailing tool updates until cancelled stop',
    () async {
      final cancelReceived = Completer<void>();
      agent.connection.onNotification('session/cancel', (params) {
        if (!cancelReceived.isCompleted) cancelReceived.complete();
      });
      scriptPrompt(() async {
        await cancelReceived.future;
        agentCtx.sessionUpdate(
          sessionId: sessionId,
          update: acpd.ToolCallStatusUpdate(
            update: acpd.ToolCallUpdate(
              toolCallId: 'tc-late',
              title: 'Wrapping up',
              status: acpd.ToolCallStatus.completed,
            ),
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.cancelled,
        ).toJson();
      });

      await openSession();

      final events = <AcpSessionUpdate>[];
      final sub = session.updates.listen(events.add);
      final promptDone = session.prompt('go');
      await pumpEventQueue();
      session.cancel();
      await promptDone;
      await pumpEventQueue();
      sub.cancel();

      expect(events, [
        const AcpToolCallUpdate(
          toolCallId: 'tc-late',
          title: 'Wrapping up',
          status: AcpToolCallStatus.completed,
        ),
        const AcpStop(kind: AcpStopKind.cancelled),
      ]);
      expect(events.whereType<AcpStop>().single.message, isNull);
    },
  );

  test(
    'permission timeout resolves null and sends the cancelled default',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-t'),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-t',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession(permissionTimeout: const Duration(milliseconds: 50));
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      final events = <AcpSessionUpdate>[];
      final sub = session.updates.listen(events.add);
      // No answer is given; the hold times out.
      await session.prompt('go');
      await pumpEventQueue();
      sub.cancel();

      expect(outcome, isA<acpd.PermissionCancelled>());
      expect(events.last, const AcpStop(kind: AcpStopKind.endTurn));

      // The late answer finds no held request.
      final late = await session.answerPermission(
        AgentPermissionReplyKind.allowOnce,
      );
      expect(late, isNull);
    },
  );

  test(
    'handshake bash permission is auto-allowed even if later policy is Ask',
    () async {
      acpd.RequestPermissionOutcome? handshakeOutcome;
      agent.connection.onRequest('session/new', (params) async {
        handshakeOutcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-hs',
              title: 'Run npm install',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'always-hs',
                name: 'Always allow',
                kind: acpd.PermissionOptionKind.allowAlways,
              ),
            ],
          ),
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      await openSession();
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      expect(handshakeOutcome, isA<acpd.PermissionSelected>());
      expect(
        (handshakeOutcome! as acpd.PermissionSelected).optionId,
        'always-hs',
      );

      acpd.RequestPermissionOutcome? afterOutcome;
      AgentPermissionRequest? captured;
      scriptPrompt(() async {
        afterOutcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-bash',
              title: 'Run npm install',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'allow-1',
                name: 'Yes',
                kind: acpd.PermissionOptionKind.allowOnce,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
        session.answerPermission(AgentPermissionReplyKind.allowOnce);
      });
      await session.prompt('go');
      await pumpEventQueue();
      permissionSub.cancel();

      expect(captured, isNotNull);
      expect(captured!.description, 'Run npm install');
      expect(afterOutcome, isA<acpd.PermissionSelected>());
      expect((afterOutcome! as acpd.PermissionSelected).optionId, 'allow-1');
    },
  );

  test(
    'handshake reject-only is cancelled; after open it surfaces a card',
    () async {
      acpd.RequestPermissionOutcome? handshakeOutcome;
      agent.connection.onRequest('session/new', (params) async {
        handshakeOutcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(toolCallId: 'hs-rej'),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-1',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
            ],
          ),
        );
        return acpd.NewSessionResponse(sessionId: sessionId).toJson();
      });

      await openSession();
      expect(handshakeOutcome, isA<acpd.PermissionCancelled>());

      acpd.RequestPermissionOutcome? afterOutcome;
      AgentPermissionRequest? captured;
      scriptPrompt(() async {
        afterOutcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-rej',
              title: 'Run npm install',
            ),
            options: const [
              acpd.PermissionOption(
                optionId: 'reject-1',
                name: 'Reject',
                kind: acpd.PermissionOptionKind.rejectOnce,
              ),
            ],
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
        session.answerPermission(AgentPermissionReplyKind.reject);
      });
      await session.prompt('go');
      await pumpEventQueue();
      permissionSub.cancel();

      expect(captured, isNotNull);
      expect(afterOutcome, isA<acpd.PermissionCancelled>());
    },
  );

  test(
    'Full access auto-allows bash without a card and prefers allow-always',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-fa',
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
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      final cards = <AgentPermissionRequest>[];
      final permissionSub = session.permissionRequests.listen(cards.add);
      await session.prompt('go');
      await pumpEventQueue();
      permissionSub.cancel();

      expect(cards, isEmpty);
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'always-1');
    },
  );

  test('Ask surfaces bash cards but auto-allows teammate-bus titles', () async {
    acpd.RequestPermissionOutcome? busOutcome;
    acpd.RequestPermissionOutcome? bashOutcome;
    scriptPrompt(() async {
      busOutcome = await requestPermission(
        acpd.RequestPermissionRequest(
          sessionId: sessionId,
          toolCall: const acpd.ToolCallUpdate(
            toolCallId: 'perm-bus',
            title: 'teammate-bus-read_messages: read_messages',
          ),
          options: const [
            acpd.PermissionOption(
              optionId: 'always-bus',
              name: 'Always allow',
              kind: acpd.PermissionOptionKind.allowAlways,
            ),
          ],
        ),
      );
      bashOutcome = await requestPermission(
        acpd.RequestPermissionRequest(
          sessionId: sessionId,
          toolCall: const acpd.ToolCallUpdate(
            toolCallId: 'perm-bash',
            title: 'Run npm install',
          ),
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

    await openSession();
    session.setPermissionPolicy(LaunchSecurityPolicy.ask);

    final cards = <AgentPermissionRequest>[];
    final permissionSub = session.permissionRequests.listen((request) {
      cards.add(request);
      session.answerPermission(AgentPermissionReplyKind.allowOnce);
    });
    await session.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(busOutcome, isA<acpd.PermissionSelected>());
    expect((busOutcome! as acpd.PermissionSelected).optionId, 'always-bus');
    expect(cards, hasLength(1));
    expect(cards.single.description, 'Run npm install');
    expect(bashOutcome, isA<acpd.PermissionSelected>());
    expect((bashOutcome! as acpd.PermissionSelected).optionId, 'allow-1');
  });

  test(
    'setPermissionPolicy(fullAccess) while bash card is held still waits for user',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-held',
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
          ),
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();
      session.setPermissionPolicy(LaunchSecurityPolicy.ask);

      final held = Completer<void>();
      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
        held.complete();
      });
      final promptDone = session.prompt('go');
      await held.future;
      await pumpEventQueue();

      expect(outcome, isNull);
      session.setPermissionPolicy(LaunchSecurityPolicy.fullAccess);
      await pumpEventQueue();
      expect(outcome, isNull);

      session.answerPermission(AgentPermissionReplyKind.allowOnce);
      await promptDone;
      permissionSub.cancel();

      expect(captured, isNotNull);
      expect(captured!.id, 'perm-held');
      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'allow-1');
    },
  );

  test('reject-only still surfaces a card under Full access', () async {
    acpd.RequestPermissionOutcome? outcome;
    scriptPrompt(() async {
      outcome = await requestPermission(
        acpd.RequestPermissionRequest(
          sessionId: sessionId,
          toolCall: const acpd.ToolCallUpdate(
            toolCallId: 'perm-rej',
            title: 'Run npm install',
          ),
          options: const [
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

    await openSession();

    AgentPermissionRequest? captured;
    final permissionSub = session.permissionRequests.listen((request) {
      captured = request;
      session.answerPermission(AgentPermissionReplyKind.reject);
    });
    await session.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(captured, isNotNull);
    expect(outcome, isA<acpd.PermissionCancelled>());
  });

  test('Cursor hyphen allow-always auto-allows without typed parse', () async {
    Object? result;
    scriptPrompt(() async {
      result = await agent.connection.sendRequest(
        'session/request_permission',
        params: {
          'sessionId': sessionId,
          'toolCall': {'toolCallId': 'perm-h', 'title': 'Run npm install'},
          'options': [
            {'optionId': 'always-1', 'name': 'Always', 'kind': 'allow-always'},
          ],
        },
        mapResult: (r) => r,
      );
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    await openSession();

    final cards = <AgentPermissionRequest>[];
    final permissionSub = session.permissionRequests.listen(cards.add);
    await session.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(cards, isEmpty);
    expect(result, {
      'outcome': {'outcome': 'selected', 'optionId': 'always-1'},
    });
  });

  test('Ask surfaces a card for Cursor hyphen option kinds', () async {
    Object? result;
    scriptPrompt(() async {
      result = await agent.connection.sendRequest(
        'session/request_permission',
        params: {
          'sessionId': sessionId,
          'toolCall': {
            'toolCallId': 'perm-hyphen-ask',
            'title': 'Run npm install',
          },
          'options': [
            {'optionId': 'allow-1', 'name': 'Yes', 'kind': 'allow-once'},
            {'optionId': 'always-1', 'name': 'Always', 'kind': 'allow-always'},
          ],
        },
        mapResult: (r) => r,
      );
      return acpd.PromptResponse(stopReason: acpd.StopReason.endTurn).toJson();
    });

    await openSession();
    session.setPermissionPolicy(LaunchSecurityPolicy.ask);

    AgentPermissionRequest? captured;
    final permissionSub = session.permissionRequests.listen((request) {
      captured = request;
      session.answerPermission(AgentPermissionReplyKind.allowOnce);
    });
    await session.prompt('go');
    await pumpEventQueue();
    permissionSub.cancel();

    expect(captured, isNotNull);
    expect(captured!.id, 'perm-hyphen-ask');
    expect(captured!.description, 'Run npm install');
    expect(captured!.always, [
      const AgentPermissionAlwaysOption(label: 'Always', payload: 'always-1'),
    ]);
    expect(result, {
      'outcome': {'outcome': 'selected', 'optionId': 'allow-1'},
    });
  });

  test('abort-shaped error after cancel becomes a cancelled stop', () async {
    scriptPrompt(() async {
      throw acpd.RpcError(
        code: acpd.ErrorCode.internalError.code,
        message: 'Request failed: This operation was aborted',
      );
    });

    await openSession();

    final events = <AcpSessionUpdate>[];
    final sub = session.updates.listen(events.add);
    session.cancel();
    await session.prompt('go');
    await pumpEventQueue();
    sub.cancel();

    expect(events, [const AcpStop(kind: AcpStopKind.cancelled)]);
  });

  test(
    'other prompt errors surface as an error stop with translated text',
    () async {
      scriptPrompt(() async {
        throw acpd.RpcError(
          code: acpd.ErrorCode.internalError.code,
          message: 'boom',
        );
      });

      await openSession();

      final events = <AcpSessionUpdate>[];
      final sub = session.updates.listen(events.add);
      await session.prompt('go');
      await pumpEventQueue();
      sub.cancel();

      final stop = events.whereType<AcpStop>().single;
      expect(stop.kind, AcpStopKind.error);
      expect(stop.message, contains('boom'));
    },
  );

  test(
    'Cursor ask_question emits AcpPendingAsk; answerAsk returns option ids',
    () async {
      await rebuildConnection(const CursorAcpTranslator());

      Object? askResult;
      scriptPrompt(() async {
        askResult = await agent.connection.sendRequest(
          'cursor/ask_question',
          params: _askParams,
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      AcpPendingClientRequest? captured;
      final requestSub = session.clientRequests.listen((pending) {
        captured = pending;
        session.answerAsk(
          AcpAskHoldReply.answered(
            const AiAskUserSubmission(
              answers: [
                ['Agent'],
              ],
              optionIndices: [0],
            ),
          ),
        );
      });
      await session.prompt('go');
      await pumpEventQueue();
      requestSub.cancel();

      expect(captured, isA<AcpPendingAsk>());
      final ask = captured! as AcpPendingAsk;
      expect(ask.toolCallId, 'ask-1');
      expect(ask.questions.single.id, 'q1');
      expect(askResult, {
        'outcome': {
          'outcome': 'answered',
          'answers': [
            {
              'questionId': 'q1',
              'selectedOptionIds': ['agent'],
            },
          ],
        },
      });
    },
  );

  test('cancel while ask is held answers the agent with cancelled', () async {
    await rebuildConnection(const CursorAcpTranslator());

    Object? askResult;
    scriptPrompt(() async {
      askResult = await agent.connection.sendRequest(
        'cursor/ask_question',
        params: _askParams,
        mapResult: (r) => r,
      );
      return acpd.PromptResponse(
        stopReason: acpd.StopReason.cancelled,
      ).toJson();
    });

    await openSession();

    final held = Completer<void>();
    final requestSub = session.clientRequests.listen((pending) {
      expect(pending, isA<AcpPendingAsk>());
      held.complete();
    });
    final promptDone = session.prompt('go');
    await held.future;
    session.cancel();
    await promptDone;
    requestSub.cancel();

    expect(askResult, {
      'outcome': {'outcome': 'cancelled'},
    });
  });

  test(
    'Cursor create_plan emits AcpPendingPlan; answerPlan returns accepted',
    () async {
      await rebuildConnection(const CursorAcpTranslator());

      Object? planResult;
      scriptPrompt(() async {
        planResult = await agent.connection.sendRequest(
          'cursor/create_plan',
          params: _planParams,
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      AcpPendingClientRequest? captured;
      final requestSub = session.clientRequests.listen((pending) {
        captured = pending;
        session.answerPlan(const AcpPlanHoldReply.accepted());
      });
      await session.prompt('go');
      await pumpEventQueue();
      requestSub.cancel();

      expect(captured, isA<AcpPendingPlan>());
      final plan = captured! as AcpPendingPlan;
      expect(plan.toolCallId, 'plan-1');
      expect(plan.planText, '# Ship it');
      expect(planResult, {
        'outcome': {'outcome': 'accepted'},
      });
    },
  );

  test(
    'Cursor update_todos notification appears on updates as AcpTodoListUpdate',
    () async {
      await rebuildConnection(const CursorAcpTranslator());

      scriptPrompt(() {
        agent.connection.notify(
          'cursor/update_todos',
          params: {
            'todos': [
              {'id': '1', 'content': 'A', 'status': 'pending'},
            ],
            'merge': true,
          },
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      final events = <AcpSessionUpdate>[];
      final sub = session.updates.listen(events.add);
      await session.prompt('go');
      await pumpEventQueue();
      sub.cancel();

      final todo = events.whereType<AcpTodoListUpdate>().single;
      expect(todo.notification.merge, isTrue);
      expect(todo.notification.todos.single.id, '1');
      expect(todo.notification.todos.single.content, 'A');
      expect(events.last, const AcpStop(kind: AcpStopKind.endTurn));
    },
  );

  test(
    'Gemini translator does not register Cursor ask_question (method-not-found)',
    () async {
      await openSession();

      await expectLater(
        agent.connection.sendRequest(
          'cursor/ask_question',
          params: _askParams,
          mapResult: (r) => r,
        ),
        throwsA(
          isA<acpd.RpcError>().having(
            (e) => e.code,
            'code',
            acpd.ErrorCode.methodNotFound.code,
          ),
        ),
      );
    },
  );

  test(
    'malformed registered ask_question encodes cancelled and does not hang',
    () async {
      await rebuildConnection(const CursorAcpTranslator());

      Object? askResult;
      scriptPrompt(() async {
        askResult = await agent.connection.sendRequest(
          'cursor/ask_question',
          params: const {'toolCallId': 'bad'},
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      final pending = <AcpPendingClientRequest>[];
      final requestSub = session.clientRequests.listen(pending.add);
      await session.prompt('go');
      await pumpEventQueue();
      requestSub.cancel();

      expect(pending, isEmpty);
      expect(askResult, {
        'outcome': {'outcome': 'cancelled'},
      });
    },
  );

  test(
    'unknown registered blocking method encodes cancelled and does not hang',
    () async {
      await rebuildConnection(const _UnknownBlockingTranslator());

      Object? result;
      scriptPrompt(() async {
        result = await agent.connection.sendRequest(
          'cursor/mystery',
          params: const {'foo': 'bar'},
          mapResult: (r) => r,
        );
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      await session.prompt('go');
      await pumpEventQueue();

      expect(result, {
        'outcome': {'outcome': 'cancelled'},
      });
    },
  );
}

const _askParams = {
  'toolCallId': 'ask-1',
  'questions': [
    {
      'id': 'q1',
      'prompt': 'Mode?',
      'options': [
        {'id': 'agent', 'label': 'Agent'},
        {'id': 'plan', 'label': 'Plan'},
      ],
    },
  ],
};

const _planParams = {
  'toolCallId': 'plan-1',
  'plan': '# Ship it',
  'name': 'Ship',
  'overview': 'Do the thing',
};

acpd.SessionConfigOption _modelOption(String current) {
  return acpd.SessionConfigSelectOptionValue(
    id: 'model',
    name: 'Model',
    currentValue: current,
    category: acpd.SessionConfigOptionCategory.model,
    options: acpd.SessionConfigUngroupedOptions([
      const acpd.SessionConfigSelectOption(value: 'sonnet', name: 'Sonnet'),
      const acpd.SessionConfigSelectOption(value: 'opus', name: 'Opus'),
    ]),
  );
}

final class _UnknownBlockingTranslator extends AcpAgentTranslator {
  const _UnknownBlockingTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const ['cursor/mystery'];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) =>
      error.toString();
}

/// Bridges an acpd_test in-memory transport into our byte-pipe [AcpTransport].
///
/// Re-encodes each acpd [acpd.TransportFrame] into an NDJSON byte chunk so the
/// connection under test exercises the same decode path as a real process
/// (same bridge as `acp_connection_test.dart`).
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
