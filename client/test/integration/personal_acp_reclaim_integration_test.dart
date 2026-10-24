@Tags(['integration'])
library;

import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/catalog/chat_data_snapshot.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/runtime/pty/terminal_reclaim_policy.dart';
import 'package:teampilot/services/chat/runtime/tab_member_reclaim_watch.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart'
    show SessionLifecycleService;
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../support/in_memory_filesystem.dart';
import '../support/stub_tab_member_materializer.dart';

/// Personal (terminal-less) ACP idle reclaim + restore, wired across the real
/// reclaim watch and the launch-service discard/attach seams.
///
/// The personal runtime is hidden (another session is centre-active), so the
/// reclaim watch discards it through the production callback; a later
/// `attachAcpRuntime` re-attaches a fresh cubit and clears `reclaimedAcpRuntime`.
/// The ACP runtime is faked so the test needs no live adapter.
void main() {
  test(
    'idle hidden personal ACP runtime is reclaimed and re-attached on demand',
    () async {
      final harness = _Harness();
      final session = _personalSession();
      harness.tab.persistedSession = session;
      final job = _job(session);

      // Boot the personal ACP runtime.
      final handled = await harness.service.attachAcpRuntime(job, session);
      expect(handled, isTrue);
      final firstCubit = harness.tab.acpRuntime;
      expect(firstCubit, isNotNull);
      expect(harness.tab.reclaimedAcpRuntime, isFalse);

      // Idle at the prompt so the policy can reclaim it.
      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();
      expect(firstCubit!.state.phase, AcpChatPhase.idle);

      // Hidden tab + deterministic clock → discarded.
      var now = DateTime(2026, 8, 9, 12, 0, 0);
      final watch = _watch(harness, () => now);
      watch.tick();
      now = now.add(const Duration(seconds: 5));
      watch.tick();

      expect(
        harness.tab.acpRuntime,
        isNull,
        reason: 'the idle hidden personal runtime must be discarded',
      );
      expect(harness.tab.reclaimedAcpRuntime, isTrue);
      await pumpEventQueue();
      expect(firstCubit.isClosed, isTrue);

      // Restore: the attach funnel brings a fresh cubit and clears the flag.
      final reattached = await harness.service.attachAcpRuntime(job, session);
      final secondCubit = harness.tab.acpRuntime;
      expect(reattached, isTrue);
      expect(secondCubit, isNotNull);
      expect(identical(secondCubit, firstCubit), isFalse);
      expect(secondCubit!.isClosed, isFalse);
      expect(harness.tab.reclaimedAcpRuntime, isFalse);

      await secondCubit.close();
      watch.dispose();
    },
  );
}

TabMemberReclaimWatch _watch(_Harness harness, DateTime Function() now) {
  return TabMemberReclaimWatch(
    tabStore: harness.tabStore,
    reclaimEnabled: () => true,
    activeTeam: () => null,
    policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
    onDiscardMember: (_, __) {},
    now: now,
    acpPolicy: () =>
        const TerminalReclaimPolicy(idleAfter: Duration(seconds: 4)),
    // Some other tab is centre-active → the personal runtime is hidden.
    activeSessionId: () => 'other',
    onDiscardPersonalAcp: harness.service.discardPersonalAcpRuntime,
  );
}

class _Harness {
  _Harness() {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) => runtime,
      prepareAcpContribution: (session, workspace) async => const {},
    );
  }

  final runtime = _ControllableAcpRuntime();
  final tabStore = ChatTabStore(storage: fakeHomeStorage());
  final tab = ChatTab(
    info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
    cliTeamName: '',
  );
  late final SessionLaunchService service;
}

AppSession _personalSession() => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  cli: CliTool.claude,
  acp: true,
  createdAt: 1,
);

SessionConnectJob _job(AppSession session) {
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  return SessionConnectJob(
    session: session,
    request: SessionOpenRequest(session: session, workspace: workspace),
    generation: 1,
    workspace: workspace,
    reason: LaunchReason.restore,
  );
}

class _FakeLifecycle implements SessionLifecycleService {
  @override
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => RuntimeTarget.local();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore) : memberMaterializer = stubTabMemberMaterializer(tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  @override
  SessionLifecycleService get lifecycle => _FakeLifecycle();

  @override
  bool get isClosed => false;

  @override
  ChatSessionShellFactory get shellFactory =>
      ChatSessionShellFactory(executableResolver: () => '/usr/bin/claude');

  @override
  CliToolRegistry get cliRegistry => CliToolRegistry.builtIn();

  @override
  ChatDataSnapshot stateSnapshot() => const ChatDataSnapshot(
    workspaces: [],
    sessions: [],
    visibleWorkspaces: [],
    visibleSessions: [],
  );

  @override
  void updateTabRunning(String tabId) {}

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  void clearLaunchError(String sessionId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _ControllableAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();

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
  Future<void> prompt(String text) async {}

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
