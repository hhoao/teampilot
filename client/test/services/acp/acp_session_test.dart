import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:acpd_test/acpd_test.dart' as acpd_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/acp/acp_connection.dart';
import 'package:teampilot/services/acp/acp_frame_logger.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_transport.dart';
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

  /// Scripts the agent's `session/prompt` handler.
  void scriptPrompt(FutureOr<Object?> Function() body) {
    agent.connection.onRequest('session/prompt', (params) => body());
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

  test(
    'permission request racing dispose answers cancelled without throwing',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await agentCtx.requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-d'),
            options: const [
              acpd.PermissionOption(
                optionId: 'allow-d',
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

      await openSession();

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
    'permission request surfaces; allowOnce selects the allow option',
    () async {
      acpd.RequestPermissionOutcome? outcome;
      scriptPrompt(() async {
        outcome = await agentCtx.requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(
              toolCallId: 'perm-1',
              title: 'Run `npm install`',
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
        agentCtx.sessionUpdate(sessionId: sessionId, update: message('done'));
        return acpd.PromptResponse(
          stopReason: acpd.StopReason.endTurn,
        ).toJson();
      });

      await openSession();

      AgentPermissionRequest? captured;
      final permissionSub = session.permissionRequests.listen((request) {
        captured = request;
        session.answerPermission(AgentPermissionReplyKind.allowOnce);
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
      expect(captured!.always, [
        const AgentPermissionAlwaysOption(
          label: 'Always allow',
          payload: 'always-1',
        ),
      ]);

      expect(outcome, isA<acpd.PermissionSelected>());
      expect((outcome! as acpd.PermissionSelected).optionId, 'allow-1');

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
          firstOutcome = await agentCtx.requestPermission(
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
          secondOutcome = await agentCtx.requestPermission(
            acpd.RequestPermissionRequest(
              sessionId: sessionId,
              toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-b'),
              options: const [
                acpd.PermissionOption(
                  optionId: 'allow-b',
                  name: 'Yes',
                  kind: acpd.PermissionOptionKind.allowOnce,
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
        outcome = await agentCtx.requestPermission(
          acpd.RequestPermissionRequest(
            sessionId: sessionId,
            toolCall: const acpd.ToolCallUpdate(toolCallId: 'perm-t'),
            options: const [
              acpd.PermissionOption(
                optionId: 'allow-t',
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

      await openSession(permissionTimeout: const Duration(milliseconds: 50));

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
