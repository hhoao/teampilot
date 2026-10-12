import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('attachAcpRuntime requires session.cli instead of defaulting', () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    tabStore.registerSession(
      ChatTab(
        info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
        cliTeamName: '',
      ),
    );
    final service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      acp: true,
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
    final job = SessionConnectJob(
      session: session,
      request: SessionOpenRequest(session: session, workspace: workspace),
      generation: 1,
      workspace: workspace,
      reason: LaunchReason.create,
    );

    await expectLater(
      service.attachAcpRuntime(job, session),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'ACP session requires session.cli',
        ),
      ),
    );
  });

  test(
    'attachAcpRuntime passes contributeLaunch env into the ACP spawn',
    () async {
      final tabStore = ChatTabStore(storage: fakeHomeStorage())
        ..setActiveWorkspaceId('w1');
      final tab = ChatTab(
        info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
        cliTeamName: '',
      );
      tabStore.registerSession(tab);
      final runtime = _RecordingAcpRuntime();
      var contributionCalls = 0;
      final service = SessionLaunchService(
        _Host(tabStore),
        storage: fakeHomeStorage(),
        acpRuntimeFactory: ({required logger, required tool}) {
          return runtime;
        },
        prepareAcpContribution: (session, workspace) async {
          contributionCalls++;
          expect(session.sessionId, 's1');
          expect(workspace.workspaceId, 'w1');
          return const {
            'CLAUDE_CONFIG_DIR': '/runtime/s1/claude',
            'CLAUDE_CODE_NO_FLICKER': '1',
          };
        },
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.claude,
        acp: true,
        createdAt: 1,
      );
      final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
      final job = SessionConnectJob(
        session: session,
        request: SessionOpenRequest(session: session, workspace: workspace),
        generation: 1,
        workspace: workspace,
        reason: LaunchReason.create,
      );

      await service.attachAcpRuntime(job, session);

      expect(contributionCalls, 1);
      expect(runtime.started, isTrue);
      expect(runtime.baseEnv['CLAUDE_CONFIG_DIR'], '/runtime/s1/claude');
      expect(runtime.baseEnv['CLAUDE_CODE_NO_FLICKER'], '1');
      expect(tab.acpRuntime, isNotNull);
    },
  );

  test(
    'attachAcpRuntime injects Codex ACP strings for Codex sessions',
    () async {
      final tabStore = ChatTabStore(storage: fakeHomeStorage())
        ..setActiveWorkspaceId('w1');
      final tab = ChatTab(
        info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
        cliTeamName: '',
      );
      tabStore.registerSession(tab);
      CliTool? seenTool;
      final host = _Host(
        tabStore,
        acpStrings: (tool) {
          seenTool = tool;
          return const AcpChatStrings(
            launchFailedVersion: 'v',
            launchFailedAdapter: 'codex-adapter-missing',
            launchFailed: 'fail',
            turnFailed: 'turn',
            processExited: 'exit',
            notLoggedIn: 'codex-not-logged-in',
          );
        },
      );
      final service = SessionLaunchService(
        host,
        storage: fakeHomeStorage(),
        acpRuntimeFactory: ({required logger, required tool}) {
          return _RecordingAcpRuntime();
        },
        prepareAcpContribution: (session, workspace) async => const {},
      );
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.codex,
        acp: true,
        createdAt: 1,
      );
      final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
      final job = SessionConnectJob(
        session: session,
        request: SessionOpenRequest(session: session, workspace: workspace),
        generation: 1,
        workspace: workspace,
        reason: LaunchReason.create,
      );

      await service.attachAcpRuntime(job, session);

      expect(seenTool, CliTool.codex);
      expect(tab.acpRuntime, isNotNull);
    },
  );

  test('attachAcpRuntime for Codex passes contributeLaunch env', () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final tab = ChatTab(
      info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tabStore.registerSession(tab);
    final runtime = _RecordingAcpRuntime();
    var contributionCalls = 0;
    final service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) {
        return runtime;
      },
      prepareAcpContribution: (session, workspace) async {
        contributionCalls++;
        expect(session.sessionId, 's1');
        expect(workspace.workspaceId, 'w1');
        return const {'CODEX_HOME': '/runtime/s1/codex'};
      },
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.codex,
      acp: true,
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
    final job = SessionConnectJob(
      session: session,
      request: SessionOpenRequest(session: session, workspace: workspace),
      generation: 1,
      workspace: workspace,
      reason: LaunchReason.create,
    );

    await service.attachAcpRuntime(job, session);

    expect(contributionCalls, 1);
    expect(runtime.started, isTrue);
    expect(runtime.baseEnv['CODEX_HOME'], '/runtime/s1/codex');
    expect(tab.acpRuntime, isNotNull);
  });
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore, {this.acpStrings});

  @override
  final ChatTabStore tabStore;

  final AcpChatStrings? Function(CliTool)? acpStrings;

  @override
  AcpChatStrings? Function(CliTool tool)? get acpChatStrings => acpStrings;

  @override
  bool get isClosed => false;

  @override
  ChatSessionShellFactory get shellFactory =>
      ChatSessionShellFactory(executableResolver: () => '/usr/bin/claude');

  @override
  CliToolRegistry get cliRegistry => CliToolRegistry.builtIn();

  @override
  void updateTabRunning(String tabId) {}

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _RecordingAcpRuntime implements AcpSessionRuntimeApi {
  var started = false;
  Map<String, String> baseEnv = const {};

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) async {
    started = true;
    this.baseEnv = baseEnv;
  }

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
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async => reply;

  @override
  void cancel() {}

  @override
  Future<void> close() async {}
}
