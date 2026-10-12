import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';

const _testStrings = AcpChatStrings(
  launchFailedVersion: 'v',
  launchFailedAdapter: 'a',
  launchFailed: 'l',
  turnFailed: 't',
  processExited: 'x',
  notLoggedIn: 'Not logged in',
);

/// Minimal all-stub [AcpSessionRuntimeApi] (copied from acp_chat_runtime_cubit_test).
class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();
  final clientRequestsController =
      StreamController<AcpPendingClientRequest>.broadcast();

  bool closed = false;
  Completer<int>? agentExit;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {}

  @override
  bool get isStarted => false;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  Stream<AcpPendingClientRequest> get clientRequests =>
      clientRequestsController.stream;

  @override
  AcpAuthNotice? lastAuthNotice;

  @override
  Future<int>? get agentProcessExitCode => agentExit?.future;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async =>
      reply;

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {}

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() {}

  @override
  Future<void> close() async {
    closed = true;
    final exit = agentExit;
    if (exit != null && !exit.isCompleted) {
      exit.complete(0);
    }
  }
}

AcpChatRuntimeCubit _cubitFor(_FakeAcpRuntime runtime, {String sessionId = 's1'}) {
  return AcpChatRuntimeCubit(
    runtime: runtime,
    sessionId: sessionId,
    tool: CliTool.gemini,
  )..ensureStrings(_testStrings);
}

void main() {
  test('personal acpRuntime alias writes memberAcpRuntimes[sessionId]', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 't', subtitle: ''),
      cliTeamName: '',
    );
    expect(tab.acpRuntime, isNull);
    expect(tab.memberAcpRuntimes, isEmpty);

    final runtime = _FakeAcpRuntime();
    final cubit = _cubitFor(runtime);
    tab.acpRuntime = cubit;

    expect(tab.memberAcpRuntimes['s1'], same(cubit));
    expect(tab.acpRuntime, same(cubit));
  });

  test('acpRuntime alias keys by persistedSession.sessionId when set', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 'tab-id', title: 't', subtitle: ''),
      cliTeamName: '',
    );
    tab.persistedSession = AppSession(
      sessionId: 'persisted-s1',
      workspaceId: 'w1',
      acp: true,
      createdAt: 1,
    );

    final runtime = _FakeAcpRuntime();
    final cubit = _cubitFor(runtime, sessionId: 'persisted-s1');
    tab.acpRuntime = cubit;

    expect(tab.memberAcpRuntimes['persisted-s1'], same(cubit));
    expect(tab.memberAcpRuntimes.containsKey('tab-id'), isFalse);
    expect(tab.acpRuntime, same(cubit));

    tab.acpRuntime = null;
    expect(tab.memberAcpRuntimes, isEmpty);
    expect(tab.acpRuntime, isNull);
  });

  test('disposeBus closes every member ACP runtime', () async {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 't', subtitle: ''),
      cliTeamName: '',
    );
    final runtimeA = _FakeAcpRuntime();
    final runtimeB = _FakeAcpRuntime();
    final a = _cubitFor(runtimeA);
    final b = _cubitFor(runtimeB, sessionId: 'lead');
    tab.memberAcpRuntimes['s1'] = a;
    tab.memberAcpRuntimes['lead'] = b;
    tab.acpRuntime = a;

    await tab.disposeBus();

    expect(runtimeA.closed, isTrue);
    expect(runtimeB.closed, isTrue);
    expect(tab.memberAcpRuntimes, isEmpty);
    expect(tab.acpRuntime, isNull);
  });
}
