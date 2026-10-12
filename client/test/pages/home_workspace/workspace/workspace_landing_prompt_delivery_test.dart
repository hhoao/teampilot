import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_prompt_delivery.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';

void main() {
  late _FakeAcpRuntime runtime;
  late AcpChatRuntimeCubit cubit;

  setUp(() {
    runtime = _FakeAcpRuntime();
    cubit =
        AcpChatRuntimeCubit(
          runtime: runtime,
          sessionId: 'sess-acp',
          tool: CliTool.claude,
        )..ensureStrings(
          const AcpChatStrings(
            launchFailedVersion: 'v',
            launchFailedAdapter: 'a',
            launchFailed: 'l',
            turnFailed: 't',
            processExited: 'x',
            notLoggedIn: 'Not logged in',
          ),
        );
  });

  tearDown(() async {
    await cubit.close();
    await runtime.updatesController.close();
    await runtime.permissionsController.close();
  });

  test('ACP landing queues sendPrompt and never issues a PTY submit', () async {
    final session = AppSession(
      sessionId: 'sess-acp',
      workspaceId: 'ws',
      cli: CliTool.claude,
      acp: true,
      createdAt: 1,
    );
    var ptyCalls = 0;

    final sent = await deliverWorkspaceLandingPrompt(
      session: session,
      acpRuntime: cubit,
      memberId: 'sess-acp',
      message: 'hello from landing',
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-delivery';
      },
    );

    expect(sent, isTrue);
    expect(ptyCalls, 0);
    expect(runtime.prompts, isEmpty, reason: 'still launching → queued');
    expect(cubit.state.messages, hasLength(1));
    expect(cubit.state.messages.single.role, AiRole.user);
    await cubit.start(
      executable: 'claude-agent-acp',
      sessionToolDir: '/runtime/claude',
      workingDirectory: '/work',
    );
    await Future<void>.delayed(Duration.zero);
    expect(runtime.prompts, ['hello from landing']);
  });

  test('ACP landing does not persist a PTY pending overlay', () {
    final session = AppSession(
      sessionId: 'sess-acp',
      workspaceId: 'ws',
      cli: CliTool.claude,
      acp: true,
      createdAt: 1,
    );
    expect(
      shouldPersistLandingHistoryPending(
        switchToTerminal: false,
        session: session,
      ),
      isFalse,
    );
  });

  test('PTY landing still persists the optimistic bubble', () {
    final session = AppSession(
      sessionId: 'sess-pty',
      workspaceId: 'ws',
      cli: CliTool.claude,
      createdAt: 1,
    );
    expect(
      shouldPersistLandingHistoryPending(
        switchToTerminal: false,
        session: session,
      ),
      isTrue,
    );
    expect(
      shouldPersistLandingHistoryPending(
        switchToTerminal: true,
        session: session,
      ),
      isFalse,
    );
  });

  test('ACP landing without a runtime is not a PTY submit', () async {
    final session = AppSession(
      sessionId: 'sess-acp',
      workspaceId: 'ws',
      cli: CliTool.claude,
      acp: true,
      createdAt: 1,
    );
    var ptyCalls = 0;

    final sent = await deliverWorkspaceLandingPrompt(
      session: session,
      acpRuntime: null,
      memberId: 'sess-acp',
      message: 'hello',
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-delivery';
      },
    );

    expect(sent, isFalse);
    expect(ptyCalls, 0);
  });

  test('PTY landing still uses direct submit', () async {
    final session = AppSession(
      sessionId: 'sess-pty',
      workspaceId: 'ws',
      cli: CliTool.claude,
      createdAt: 1,
    );
    String? seenMessage;

    final sent = await deliverWorkspaceLandingPrompt(
      session: session,
      acpRuntime: cubit,
      memberId: 'sess-pty',
      message: 'via pty',
      ptySubmit: (sessionId, memberId, message) async {
        seenMessage = message;
        return 'ok';
      },
    );

    expect(sent, isTrue);
    expect(seenMessage, 'via pty');
    expect(runtime.prompts, isEmpty);
  });

  test('ACP landing queues sendPrompt before handshake finishes', () async {
    final connect = Completer<bool>();

    final resultFuture = queueAcpLandingPromptDuringConnect(
      connect: connect.future,
      lookup: () => cubit,
      cancelled: () => false,
      message: 'hello from landing',
      pollInterval: const Duration(milliseconds: 1),
    );

    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.messages, hasLength(1));
    expect(cubit.state.messages.single.role, AiRole.user);
    expect(connect.isCompleted, isFalse);

    connect.complete(true);
    final result = await resultFuture;
    expect(result.connected, isTrue);
    expect(result.queued, isTrue);
    expect(runtime.prompts, isEmpty, reason: 'handshake still in flight');
  });
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();
  final prompts = <String>[];
  bool started = false;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {
    started = true;
  }

  @override
  bool get isStarted => started;

  @override
  String get sessionId => 'acp-1';

  @override
  Future<void> prompt(String text) async => prompts.add(text);

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  Stream<AcpPendingClientRequest> get clientRequests => const Stream.empty();

  @override
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async => reply;

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {}

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() {}

  @override
  Future<void> close() async {}
}
