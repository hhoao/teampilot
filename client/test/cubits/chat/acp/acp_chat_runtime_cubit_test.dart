import 'dart:async';
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_chat_transcript.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import '../../../support/in_memory_filesystem.dart';

/// All-stub [AcpSessionRuntimeApi] for cubit tests.
class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();

  Object? startError;
  bool started = false;
  bool closed = false;
  bool cancelled = false;
  final List<String> prompts = [];
  ({AgentPermissionReplyKind kind, AgentPermissionAlwaysOption? always})?
  lastAnswer;

  /// Exit-code future the cubit's exit watcher observes (null = never).
  Completer<int>? agentExit;

  void emit(AcpSessionUpdate update) => updatesController.add(update);

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {
    if (startError != null) throw startError!;
    started = true;
  }

  @override
  bool get isStarted => started;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {
    prompts.add(text);
  }

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  AcpAuthNotice? lastAuthNotice;

  @override
  Future<int>? get agentProcessExitCode => agentExit?.future;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async {
    lastAnswer = (kind: reply, always: always);
    return reply;
  }

  @override
  void cancel() => cancelled = true;

  @override
  Future<void> close() async {
    closed = true;
    // Production `_runtime.close()` awaits process exit; SIGTERM typically
    // completes [agentExit] with 0 before the cubit finishes closing.
    final exit = agentExit;
    if (exit != null && !exit.isCompleted) {
      exit.complete(0);
    }
  }
}

const _testStrings = AcpChatStrings(
  launchFailedVersion: 'Gemini ACP unsupported',
  launchFailedAdapter: 'Adapter missing',
  launchFailed: 'Failed to start the agent',
  turnFailed: 'Turn failed',
  processExited: 'Process exited',
  notLoggedIn: 'Not logged in',
);

void main() {
  late _FakeAcpRuntime runtime;

  setUp(() {
    runtime = _FakeAcpRuntime();
  });

  tearDown(() async {
    await runtime.updatesController.close();
    await runtime.permissionsController.close();
  });

  AcpChatRuntimeCubit bootCubit({
    AgentAttentionCubit? attention,
    AcpChatTranscriptWriter? transcript,
  }) {
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
      attention: attention,
      transcript: transcript,
    )..ensureStrings(_testStrings);
    return cubit;
  }

  test('start completes → ready phase', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(cubit.state.phase, AcpChatPhase.ready);
    expect(cubit.state.inTurn, isFalse);
    await cubit.close();
  });

  test(
    'handshake kind=none is not a chat row — the CLI probe is reporting-only',
    () async {
      runtime.lastAuthNotice = const AcpAuthNotice(
        loggedIn: false,
        message: 'Not logged in',
      );
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      await pumpEventQueue();
      expect(cubit.state.phase, AcpChatPhase.ready);
      expect(cubit.state.messages, isEmpty);
      await cubit.close();
    },
  );

  test(
    'later logged-in auth notice is silent when no warning was shown',
    () async {
      runtime.lastAuthNotice = const AcpAuthNotice(
        loggedIn: false,
        message: 'Not logged in',
      );
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      await pumpEventQueue();
      expect(cubit.state.messages, isEmpty);

      runtime.emit(const AcpAuthNotice(loggedIn: true, message: 'Claude Pro'));
      await pumpEventQueue();
      expect(cubit.state.messages, isEmpty);
      await cubit.close();
    },
  );

  test('assistant stream is unaffected by a handshake none probe', () async {
    runtime.lastAuthNotice = const AcpAuthNotice(
      loggedIn: false,
      message: 'Not logged in',
    );
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    await pumpEventQueue();
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.messages, hasLength(1));
    expect(cubit.state.messages.single.role, AiRole.assistant);
    await cubit.close();
  });

  test('sendPrompt during launching is flushed after start', () async {
    final cubit = bootCubit();
    expect(cubit.sendPrompt('hello'), isTrue);
    expect(runtime.prompts, isEmpty);
    expect(cubit.state.messages.single.role, AiRole.user);
    expect(
      (cubit.state.messages.single.parts.single as AiTextPart).text,
      'hello',
    );
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    await pumpEventQueue();
    expect(runtime.prompts, ['hello']);
    expect(cubit.state.messages, hasLength(1));
    expect(cubit.state.messages.single.role, AiRole.user);
    await cubit.close();
  });

  test(
    'queued landing prompt is not preceded by a handshake not-logged-in row',
    () async {
      runtime.lastAuthNotice = const AcpAuthNotice(
        loggedIn: false,
        message: 'Not logged in',
      );
      final cubit = bootCubit();
      expect(cubit.sendPrompt('hello'), isTrue);
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      await pumpEventQueue();
      expect(cubit.state.messages, hasLength(1));
      expect(cubit.state.messages.single.role, AiRole.user);
      expect(
        (cubit.state.messages.single.parts.single as AiTextPart).text,
        'hello',
      );
      await cubit.close();
    },
  );

  test(
    'sendPrompt after handshake warning replaces it with the user row',
    () async {
      runtime.lastAuthNotice = const AcpAuthNotice(
        loggedIn: false,
        message: 'Not logged in',
      );
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      await pumpEventQueue();
      expect(cubit.state.messages, isEmpty);

      expect(cubit.sendPrompt('hello'), isTrue);
      await pumpEventQueue();
      expect(cubit.state.messages, hasLength(1));
      expect(cubit.state.messages.single.role, AiRole.user);
      expect(
        (cubit.state.messages.single.parts.single as AiTextPart).text,
        'hello',
      );
      await cubit.close();
    },
  );

  test(
    'message chunk + end_turn stop → one assistant message + idle',
    () async {
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'Hello',
          isThought: false,
        ),
      );
      runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();

      expect(cubit.state.messages, hasLength(1));
      final message = cubit.state.messages.single;
      expect(message.role, AiRole.assistant);
      final part = message.parts.single;
      expect(part, isA<AiTextPart>());
      expect((part as AiTextPart).text, 'Hello');
      expect(cubit.state.phase, AcpChatPhase.idle);
      expect(cubit.state.inTurn, isFalse);
      await cubit.close();
    },
  );

  test('thought chunk maps to a collapsed reasoning part', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'thinking...',
        isThought: true,
      ),
    );
    await pumpEventQueue();

    final message = cubit.state.messages.single;
    expect(message.parts.single, isA<AiReasoningPart>());
    expect(aiMessageIsThinkingOnly(message), isTrue);
    await cubit.close();
  });

  test('consecutive thought chunks coalesce into one reasoning part', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'think',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'ing…',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: ' more',
        isThought: true,
      ),
    );
    await pumpEventQueue();

    final message = cubit.state.messages.single;
    expect(
      message.parts,
      hasLength(1),
      reason: 'streaming thoughts are one step',
    );
    expect(message.parts.single, isA<AiReasoningPart>());
    expect((message.parts.single as AiReasoningPart).text, 'thinking… more');
    await cubit.close();
  });

  test(
    'consecutive text chunks coalesce; thought stays a separate part',
    () async {
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'think',
          isThought: true,
        ),
      );
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'ing',
          isThought: true,
        ),
      );
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'Hello',
          isThought: false,
        ),
      );
      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: ' world',
          isThought: false,
        ),
      );
      await pumpEventQueue();

      final parts = cubit.state.messages.single.parts;
      expect(parts, hasLength(2));
      expect((parts[0] as AiReasoningPart).text, 'thinking');
      expect((parts[1] as AiTextPart).text, 'Hello world');
      await cubit.close();
    },
  );

  test('empty stream chunks do not open extra parts', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'ok',
        isThought: false,
      ),
    );
    await pumpEventQueue();

    expect(cubit.state.messages.single.parts, hasLength(1));
    expect((cubit.state.messages.single.parts.single as AiTextPart).text, 'ok');
    await cubit.close();
  });

  test('tool call update → tool card part with status lifecycle', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'read file',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    await pumpEventQueue();
    var part = cubit.state.messages.single.parts.single as AiToolCallPart;
    expect(part.toolCallId, 't1');
    expect(part.toolName, 'read file');
    expect(part.status, AiToolCallStatus.running);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.messages, hasLength(1));
    part = cubit.state.messages.single.parts.single as AiToolCallPart;
    expect(part.status, AiToolCallStatus.complete);
    expect(part.isError, isFalse);
    await cubit.close();
  });

  test('activity walks thinking → generating → toolRunning → generating → none', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(cubit.state.activity, AcpChatActivity.none);

    cubit.sendPrompt('hi');
    expect(cubit.state.activity, AcpChatActivity.thinking);

    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'he',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'read file',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.none);
    await cubit.close();
  });

  test('two overlapping tool calls keep toolRunning until both end', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('go');
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't2',
        status: AcpToolCallStatus.pending,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.toolRunning);

    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't2',
        status: AcpToolCallStatus.failed,
      ),
    );
    await pumpEventQueue();
    // Neither tool terminated the turn, and no chunk has arrived: back to the
    // pre-first-token state.
    expect(cubit.state.activity, AcpChatActivity.thinking);
    await cubit.close();
  });

  test('a chunk with no visible text still moves thinking → generating', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('go');
    expect(cubit.state.activity, AcpChatActivity.thinking);

    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    expect(cubit.state.activity, AcpChatActivity.generating);
    // Only the user bubble exists — the empty chunk added no message.
    expect(cubit.state.messages, hasLength(1));
    await cubit.close();
  });

  test('cancelled stop is silent — no system message, idle', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'partial',
        isThought: false,
      ),
    );
    runtime.emit(const AcpStop(kind: AcpStopKind.cancelled));
    await pumpEventQueue();

    expect(cubit.state.messages, hasLength(1));
    expect(cubit.state.messages.single.role, AiRole.assistant);
    expect(cubit.state.phase, AcpChatPhase.idle);
    await cubit.close();
  });

  test('error stop → inline system message via strings + idle', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(const AcpStop(kind: AcpStopKind.error, message: 'boom'));
    await pumpEventQueue();

    expect(cubit.state.phase, AcpChatPhase.idle);
    final message = cubit.state.messages.single;
    expect(message.role, AiRole.system);
    expect((message.parts.single as AiTextPart).text, contains('boom'));
    expect((message.parts.single as AiTextPart).text, contains('Turn failed'));
    await cubit.close();
  });

  test(
    'permission request → pending card + attention waiting; answer delegates',
    () async {
      final attention = AgentAttentionCubit(pruneInterval: null);
      final cubit = bootCubit(attention: attention);
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      const request = AgentPermissionRequest(
        id: 'perm-1',
        description: 'Run npm install',
        always: [AgentPermissionAlwaysOption(label: 'Bash', payload: 'opt-9')],
      );
      runtime.permissionsController.add(request);
      await pumpEventQueue();

      expect(cubit.state.pendingPermission, request);
      expect(
        attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
        AgentSeatAttention.waiting,
      );

      final delivered = await cubit.answerPermission(
        AgentPermissionReplyKind.always,
        alwaysPayload: 'opt-9',
      );
      expect(delivered, isTrue);
      expect(cubit.state.pendingPermission, isNull);
      expect(runtime.lastAnswer?.kind, AgentPermissionReplyKind.always);
      expect(runtime.lastAnswer?.always?.payload, 'opt-9');
      expect(
        attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
        AgentSeatAttention.working,
      );
      await cubit.close();
      await attention.close();
    },
  );

  test('AcpLaunchException → inline error message + ended phase', () async {
    runtime.startError = AcpLaunchException(reason: acpLaunchFailedVersion);
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );

    expect(cubit.state.phase, AcpChatPhase.ended);
    expect(cubit.state.error?.kind, AcpChatErrorKind.launchFailedVersion);
    final message = cubit.state.messages.single;
    expect(message.role, AiRole.system);
    expect(
      (message.parts.single as AiTextPart).text,
      contains('Gemini ACP unsupported'),
    );
    await cubit.close();
  });

  test('adapter launch failure → launchFailedAdapter kind + copy', () async {
    runtime.startError = AcpLaunchException(reason: acpLaunchFailedAdapter);
    final cubit = bootCubit();
    await cubit.start(
      executable: 'claude',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );

    expect(cubit.state.phase, AcpChatPhase.ended);
    expect(cubit.state.error?.kind, AcpChatErrorKind.launchFailedAdapter);
    expect(
      (cubit.state.messages.single.parts.single as AiTextPart).text,
      'Adapter missing',
    );
    await cubit.close();
  });

  test(
    'generic launch failure → launchFailed kind + localized copy (not raw)',
    () async {
      runtime.startError = StateError('ProcessException: gemini not found');
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );

      expect(cubit.state.phase, AcpChatPhase.ended);
      expect(cubit.state.error?.kind, AcpChatErrorKind.launchFailed);
      final message = cubit.state.messages.single;
      expect(message.role, AiRole.system);
      expect(
        (message.parts.single as AiTextPart).text,
        'Failed to start the agent',
      );
      // The raw exception text must not leak into the user-facing message.
      expect(
        (message.parts.single as AiTextPart).text,
        isNot(contains('ProcessException')),
      );
      await cubit.close();
    },
  );

  test('sendPrompt guards concurrent turns (sequential only)', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(cubit.sendPrompt('first'), isTrue);
    expect(cubit.state.inTurn, isTrue);
    expect(cubit.sendPrompt('second'), isFalse);
    await pumpEventQueue();
    expect(runtime.prompts, ['first']);
    expect(cubit.state.messages.single.role, AiRole.user);
    expect(
      (cubit.state.messages.single.parts.single as AiTextPart).text,
      'first',
    );

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(cubit.state.inTurn, isFalse);
    expect(cubit.sendPrompt('second'), isTrue);
    await pumpEventQueue();
    expect(runtime.prompts, ['first', 'second']);
    await cubit.close();
  });

  test('process exit → inline crash message + ended phase', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.handleProcessExited(1);

    expect(cubit.state.phase, AcpChatPhase.ended);
    expect(cubit.state.error?.kind, AcpChatErrorKind.processExited);
    final message = cubit.state.messages.single;
    expect(message.role, AiRole.system);
    expect((message.parts.single as AiTextPart).text, contains('1'));
    // Ended runtime must not accept further prompts.
    expect(cubit.sendPrompt('late'), isFalse);
    await cubit.close();
  });

  test(
    'agent exit watcher: transport exit after start → crash message + ended',
    () async {
      runtime.agentExit = Completer<int>();
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      expect(cubit.state.phase, AcpChatPhase.ready);

      // Mid-turn crash: the watcher must fire without any other signal.
      cubit.sendPrompt('do something');
      runtime.agentExit!.complete(1);
      await pumpEventQueue();

      expect(cubit.state.phase, AcpChatPhase.ended);
      expect(cubit.state.error?.kind, AcpChatErrorKind.processExited);
      final message = cubit.state.messages.last;
      expect(message.role, AiRole.system);
      expect((message.parts.single as AiTextPart).text, contains('1'));
      expect(cubit.state.inTurn, isFalse);
      expect(cubit.state.pendingPermission, isNull);
      // Ended runtime must not accept further prompts.
      expect(cubit.sendPrompt('next'), isFalse);
      await cubit.close();
    },
  );

  test(
    'agent exit watcher: no exit future → watcher inert (start unaffected)',
    () async {
      final cubit = bootCubit();
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      // No agentExit completer — the watcher must not have ended anything.
      expect(cubit.state.phase, AcpChatPhase.ready);
      await cubit.close();
    },
  );

  test('messages are recorded into the app-side transcript store', () async {
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    final cubit = bootCubit(transcript: transcript);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('hi');
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
    );
    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();

    final bytes = fs.byteFiles['/tp/acp.jsonl'];
    expect(bytes, isNotNull);
    final lines = utf8
        .decode(bytes!)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
    final types = lines.map((entry) => entry['type']).toList();
    expect(types, containsAll(<String>['user', 'chunk', 'stop']));
    await cubit.close();
  });

  test('start hydrates prior transcript into messages', () async {
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    final live = bootCubit(transcript: transcript);
    await live.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    live.sendPrompt('hi');
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
    );
    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    final liveShape = _messageShape(live.state.messages);
    await live.close();

    await runtime.updatesController.close();
    await runtime.permissionsController.close();
    runtime = _FakeAcpRuntime();
    final restored = bootCubit(transcript: transcript);
    await restored.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(_messageShape(restored.state.messages), liveShape);
    await restored.close();
  });

  test('hydrated history suppresses the handshake not-logged-in row', () async {
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    await transcript.recordUserPrompt('hi');
    await transcript.recordChunk(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hello',
        isThought: false,
      ),
    );
    runtime.lastAuthNotice = const AcpAuthNotice(
      loggedIn: false,
      message: 'Not logged in',
    );
    final cubit = bootCubit(transcript: transcript);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    await pumpEventQueue();
    expect(cubit.state.messages, hasLength(2));
    expect(cubit.state.messages[0].role, AiRole.user);
    expect(cubit.state.messages[1].role, AiRole.assistant);
    await cubit.close();
  });

  test(
    'start keeps an in-memory landing prompt after hydrating history',
    () async {
      final fs = InMemoryFilesystem();
      final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
      await transcript.recordUserPrompt('old');
      await transcript.recordChunk(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'prior',
          isThought: false,
        ),
      );
      final cubit = bootCubit(transcript: transcript);
      expect(cubit.sendPrompt('next'), isTrue);
      await cubit.start(
        executable: 'gemini',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      expect(cubit.state.messages, hasLength(3));
      expect((cubit.state.messages[0].parts.single as AiTextPart).text, 'old');
      expect(
        (cubit.state.messages[1].parts.single as AiTextPart).text,
        'prior',
      );
      expect(
        (cubit.state.messages.last.parts.single as AiTextPart).text,
        'next',
      );
      await cubit.close();
    },
  );

  test('intentional close does not record a process-exited crash', () async {
    runtime.agentExit = Completer<int>();
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    final cubit = bootCubit(transcript: transcript);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('hi');
    await pumpEventQueue();
    await cubit.close();
    await pumpEventQueue();

    expect(cubit.state.phase, isNot(AcpChatPhase.ended));
    final loaded = await transcript.loadMessages();
    expect(
      loaded.any(
        (m) =>
            m.role == AiRole.system &&
            (m.parts.single as AiTextPart).text.contains('Process exited'),
      ),
      isFalse,
    );
  });

  test('dispatch marks attention working; stop marks it done', () async {
    final attention = AgentAttentionCubit(pruneInterval: null);
    final cubit = bootCubit(attention: attention);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.done,
    );

    cubit.sendPrompt('do work');
    await pumpEventQueue();
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.working,
    );

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(
      attention.state.attentionFor(sessionId: 's1', memberId: 'acp'),
      AgentSeatAttention.done,
    );
    await cubit.close();
    await attention.close();
  });

  test('close cancels subscriptions and closes the runtime', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    await cubit.close();
    expect(runtime.closed, isTrue);
    // A late stop event after close must not throw or resurrect state.
    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    expect(cubit.state.phase, AcpChatPhase.ready);
  });
}

List<String> _messageShape(List<AiMessage> messages) {
  return [
    for (final message in messages)
      '${message.role.name}:${[for (final part in message.parts) switch (part) {
          AiTextPart(:final text) => 'text:$text',
          AiReasoningPart(:final text) => 'think:$text',
          AiToolCallPart(:final toolCallId, :final toolName, :final status) => 'tool:$toolCallId:$toolName:${status.name}',
        }].join('|')}',
  ];
}
