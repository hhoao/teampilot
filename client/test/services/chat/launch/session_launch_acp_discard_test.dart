import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/stub_tab_member_materializer.dart';

void main() {
  test('discardAcpSeat closes the cubit and marks it reclaimed', () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tabStore.registerSession(tab);
    final host = _Host(tabStore);
    final service = SessionLaunchService(host, storage: fakeHomeStorage());

    final readyCubit = await _readyCubit();
    tab.memberAcpRuntimes['worker-1'] = readyCubit;
    tab.membersPendingConnect.add('worker-1');

    service.discardAcpSeat('sess', 'worker-1');

    expect(tab.memberAcpRuntimes.containsKey('worker-1'), isFalse);
    expect(tab.membersPendingConnect.contains('worker-1'), isFalse);
    expect(tab.reclaimedMemberIds, contains('worker-1'));
    expect(host.clearedLaunchError, contains('sess'));
    expect(host.updatedTabRunning, contains('sess'));

    await pumpEventQueue();
    expect(readyCubit.isClosed, isTrue);
  });

  test('discardAcpSeat is a no-op for blank ids / missing tab / missing cubit',
      () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final service = SessionLaunchService(_Host(tabStore), storage: fakeHomeStorage());

    // No tab, blank ids, missing member — all must return without throwing.
    service.discardAcpSeat('', '');
    service.discardAcpSeat('sess', '');
    service.discardAcpSeat('', 'worker-1');
    service.discardAcpSeat('missing', 'worker-1');

    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tabStore.registerSession(tab);
    service.discardAcpSeat('sess', 'missing-cubit');
    expect(tab.reclaimedMemberIds, isEmpty);
  });
}

Future<AcpChatRuntimeCubit> _readyCubit() async {
  final cubit = AcpChatRuntimeCubit(
    runtime: _FakeAcpRuntime(),
    sessionId: 'sess',
    tool: CliTool.gemini,
  );
  await cubit.start(
    executable: 'gemini',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  return cubit;
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore) : memberMaterializer = stubTabMemberMaterializer(tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  final List<String> clearedLaunchError = [];
  final List<String> updatedTabRunning = [];

  @override
  bool get isClosed => false;

  @override
  ChatSessionShellFactory get shellFactory =>
      ChatSessionShellFactory(executableResolver: () => '/usr/bin/claude');

  @override
  CliToolRegistry get cliRegistry => CliToolRegistry.builtIn();

  @override
  void updateTabRunning(String tabId) => updatedTabRunning.add(tabId);

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  void clearLaunchError(String sessionId) => clearedLaunchError.add(sessionId);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  bool started = false;
  bool closed = false;

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
  }) async {
    started = true;
  }

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => started;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

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
  Future<void> close() async {
    closed = true;
  }
}
