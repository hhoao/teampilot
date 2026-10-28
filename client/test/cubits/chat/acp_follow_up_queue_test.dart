import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/conversation/follow_up/follow_up_queue.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';

import '../../support/post_frame_test_harness.dart';

/// ACP follow-ups reuse [ChatCubit.followUpQueue]: a terminal-less seat has no
/// PTY shell, so the queue gate + drainer must read the cubit's turn state and
/// deliver back into the cubit instead of the operator PTY path.
void main() {
  late _RecordingChatCubit cubit;
  late _FakeAcpRuntime runtime;
  late AcpChatRuntimeCubit acp;
  late AgentAttentionCubit attention;

  const sessionId = 'session-1';

  setUp(() async {
    setUpTestAppStorage();
    runtime = _FakeAcpRuntime();
    attention = AgentAttentionCubit(pruneInterval: null);
    acp = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: sessionId,
      tool: CliTool.gemini,
      attention: attention,
    );
    await acp.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit = _RecordingChatCubit(attention: attention)
      ..registerPersonalAcpSession(acp);
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    if (!acp.isClosed) await acp.close();
    await runtime.updatesController.close();
    await attention.close();
    tearDownTestAppStorage();
  });

  test('isMemberWorking follows the ACP cubit turn', () async {
    expect(cubit.isMemberWorking(sessionId, sessionId), isFalse);

    acp.sendPrompt('first turn');
    expect(cubit.isMemberWorking(sessionId, sessionId), isTrue);

    runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
    await _settle();
    expect(acp.state.inTurn, isFalse);
    expect(cubit.isMemberWorking(sessionId, sessionId), isFalse);
  });

  test('queued ACP follow-up waits for the idle edge then reaches the cubit '
      'and never the operator PTY path', () async {
    final seat = followUpSeatKey(sessionId, sessionId);
    acp.sendPrompt('turn one');
    await _settle();
    expect(acp.state.inTurn, isTrue);

    cubit.followUpQueue.enqueue(seat, 'queued next');
    // Same latch the compose enqueue path applies.
    cubit.notifyFollowUpMemberWorking(sessionId, sessionId, working: true);
    await _settle();

    // In-flight turn keeps the head parked.
    expect(runtime.prompts, ['turn one']);

    runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
    await _settle();

    // Draining goes through `AcpChatRuntimeCubit.sendPrompt`, not the
    // operator PTY/mailbox delivery.
    expect(runtime.prompts, ['turn one', 'queued next']);
    expect(cubit.operatorDeliveries, 0);
    expect(cubit.followUpQueue.queueFor(seat).items, isEmpty);
  });

  test('ended ACP runtime leaves the head queued for a manual retry', () async {
    final seat = followUpSeatKey(sessionId, sessionId);
    cubit.followUpQueue.enqueue(seat, 'stays queued');
    acp.handleProcessExited(1);
    await _settle();

    await cubit.resumeFollowUpQueue(sessionId, sessionId);
    await _settle();

    expect(runtime.prompts, isEmpty);
    expect(cubit.operatorDeliveries, 0);
    expect(cubit.followUpQueue.queueFor(seat).items.map((m) => m.content), [
      'stays queued',
    ]);
  });
}

/// Lets the attention stream, `_updateSessionActivities`, and the drainer's
/// async loops run to completion.
Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

final class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit({required AgentAttentionCubit attention})
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
        agentAttentionCubit: attention,
      );

  var operatorDeliveries = 0;

  void registerPersonalAcpSession(AcpChatRuntimeCubit acp) {
    final tab =
        ChatTab(
            info: const ChatTabInfo(
              id: 'session-1',
              title: 'Session',
              subtitle: '',
            ),
            cliTeamName: '',
            workspaceId: 'workspace-1',
          )
          ..persistedSession = AppSession(
            sessionId: 'session-1',
            workspaceId: 'workspace-1',
            sessionTeam: '',
            cli: CliTool.gemini,
            acp: true,
            createdAt: 0,
          );
    tab.acpRuntime = acp;
    tabStore.registerSession(tab);
  }

  @override
  Future<HistoryContinueSubmitResult> submitSessionOperatorMessage({
    required String sessionId,
    required String memberId,
    required String message,
    bool preserveWorkbenchView = true,
  }) async {
    operatorDeliveries += 1;
    return const HistoryContinueSubmitResult(
      ok: true,
      channel: HistoryContinueChannel.pty,
    );
  }
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();

  /// Every prompt the runtime accepted.
  final prompts = <String>[];

  void add(AcpSessionUpdate update) => updatesController.add(update);

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
    String? resumeSessionId,
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => true;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async => prompts.add(text);

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests => const Stream.empty();

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
