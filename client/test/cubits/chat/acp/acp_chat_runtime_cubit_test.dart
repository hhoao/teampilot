import 'dart:async';
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/acp/acp_chat_runtime_cubit.dart';
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
  Future<void> close() async => closed = true;
}

const _testStrings = AcpChatStrings(
  launchFailedVersion: 'Gemini ACP unsupported',
  turnFailed: 'Turn failed',
  processExited: 'Process exited',
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
