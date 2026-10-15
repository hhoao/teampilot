import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/catalog/chat_data_snapshot.dart';
import 'package:teampilot/services/chat/launch/connect/acp_launch_environment.dart';
import 'package:teampilot/services/chat/launch/connect/acp_runtime_attach.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/connect_shell_result.dart';
import 'package:teampilot/services/chat/launch/connect/member_connector.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session/shell_launch_spec.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart'
    show SessionLifecycleService;
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/team_bus/agent_node.dart';
import 'package:teampilot/services/chat/team_bus/team_bus.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

import '../../chat/team_bus/support/fake_member_launcher.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('mixed transcript is per member', () {
    expect(
      acpTranscriptFileName(memberId: 'lead', personal: false),
      'acp-transcript-lead.jsonl',
    );
    expect(
      acpTranscriptFileName(memberId: null, personal: true),
      'acp-transcript.jsonl',
    );
  });

  test(
    'attachMemberAcpRuntime returns false when the seat is not ACP',
    () async {
      final harness = _Harness();
      final session = _mixedSession(acp: false);
      final team = _mixedTeam();
      final member = _lead();

      final handled = await harness.service.attachMemberAcpRuntime(
        _job(session, team, member),
        session,
        (team: team, member: member, cli: CliTool.claude),
      );

      expect(handled, isFalse);
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );

  test(
    'attachMemberAcpRuntime throws when teammate-bus does not map',
    () async {
      final harness = _Harness(
        extra: const {
          'teammate-bus': {'type': 'http'},
        },
      );
      final session = _mixedSession(acp: true);
      final team = _mixedTeam();
      final member = _lead();

      await expectLater(
        harness.service.attachMemberAcpRuntime(
          _job(session, team, member),
          session,
          (team: team, member: member, cli: CliTool.claude),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'ACP teammate-bus MCP did not map to a session server',
          ),
        ),
      );
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );

  test('attachMemberAcpRuntime runs lifecycle gate before cubit.start', () async {
    final events = <String>[];
    final harness = _Harness(
      gate: ({
        required team,
        required member,
        required session,
        required sessionId,
        required teamBusInstalled,
        extraMcpServers,
      }) async {
        events.add('gate');
        return null;
      },
    );
    harness.runtime.onStart = () => events.add('start');
    final session = _mixedSession(acp: true);
    final team = _mixedTeam();
    final member = _lead();

    final handled = await harness.service.attachMemberAcpRuntime(
      _job(session, team, member),
      session,
      (team: team, member: member, cli: CliTool.claude),
    );

    expect(handled, isTrue);
    expect(events, ['gate', 'start']);
    expect(harness.tab.memberAcpRuntimes['lead'], isNotNull);
  });

  test(
    'attachMemberAcpRuntime marks the seat running and ready before start finishes',
    () async {
      final holdStart = Completer<void>();
      final harness = _Harness();
      harness.runtime.startHold = holdStart;
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      bus.declareMember(
        AgentNode.test(
          memberId: 'lead',
          lifecycle: MemberLifecycle.declared,
        ),
      );
      harness.tab.teamBus = bus;

      final attach = harness.service.attachMemberAcpRuntime(
        _job(_mixedSession(acp: true), _mixedTeam(), _lead()),
        _mixedSession(acp: true),
        (team: _mixedTeam(), member: _lead(), cli: CliTool.claude),
      );

      await pumpEventQueue();

      expect(harness.materializer.ready, [('s1', 'lead')]);
      expect(bus.memberById('lead')!.lifecycle, MemberLifecycle.running);
      expect(harness.runtime.started, isFalse);

      holdStart.complete();
      expect(await attach, isTrue);
      expect(harness.runtime.started, isTrue);
    },
  );

  test(
    'attachMemberAcpRuntime throws when lifecycle gate fails and does not start',
    () async {
      final harness = _Harness(
        gate: ({
          required team,
          required member,
          required session,
          required sessionId,
          required teamBusInstalled,
          extraMcpServers,
        }) async => ConnectShellResult.failed,
      );
      final session = _mixedSession(acp: true);
      final team = _mixedTeam();
      final member = _lead();

      await expectLater(
        harness.service.attachMemberAcpRuntime(
          _job(session, team, member),
          session,
          (team: team, member: member, cli: CliTool.claude),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ACP member lifecycle failed'),
          ),
        ),
      );
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );

  test(
    'attachMemberAcpRuntime throws when lifecycle gate defers and does not start',
    () async {
      final harness = _Harness(
        gate: ({
          required team,
          required member,
          required session,
          required sessionId,
          required teamBusInstalled,
          extraMcpServers,
        }) async => ConnectShellResult.deferred,
      );
      final session = _mixedSession(acp: true);
      final team = _mixedTeam();
      final member = _lead();

      await expectLater(
        harness.service.attachMemberAcpRuntime(
          _job(session, team, member),
          session,
          (team: team, member: member, cli: CliTool.claude),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ACP member lifecycle deferred'),
          ),
        ),
      );
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );

  test(
    'attachAcpRuntime forwards session.acpPermission to cubit.start',
    () async {
      final harness = _Harness();
      final session = _personalSession(acpPermission: LaunchSecurityPolicy.ask);

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session),
        session,
      );

      expect(handled, isTrue);
      expect(harness.runtime.started, isTrue);
      expect(harness.runtime.permissionPolicy, LaunchSecurityPolicy.ask);
      expect(harness.tab.acpRuntime, isNotNull);
    },
  );

  test(
    'attachMemberAcpRuntime forwards the binding acpPermission to cubit.start',
    () async {
      final harness = _Harness();
      final session = _mixedSession(
        acp: true,
        acpPermission: LaunchSecurityPolicy.ask,
      );
      final team = _mixedTeam();
      final member = _lead();

      final handled = await harness.service.attachMemberAcpRuntime(
        _job(session, team, member),
        session,
        (team: team, member: member, cli: CliTool.claude),
      );

      expect(handled, isTrue);
      expect(harness.runtime.started, isTrue);
      expect(harness.runtime.permissionPolicy, LaunchSecurityPolicy.ask);
    },
  );

  test(
    'attachAcpRuntime routes a remote (ssh) personal session to remote staging values',
    () async {
      final harness = _Harness(
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        remoteStaging:
            ({
              required session,
              required workspace,
              required launchTarget,
            }) async => (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {
                    'PATH': '/remote/bin',
                    'CLAUDE_CONFIG_DIR': '/remote/cfg/s1',
                  },
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/remote/cfg/s1',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: const TeamProfile(id: 't', name: 't'),
                  member: const TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '/remote/bin/claude',
            ),
        sshLaunchFactory:
            ({required session, required launchTarget}) => (
              profile: const SshProfile(
                id: 'p1',
                name: 'host',
                host: 'host',
                username: 'u',
                authType: SshAuthType.password,
              ),
              // The injected `acpRuntimeFactory` replaces the production
              // spawner, so this opener is never invoked.
              openChannel: (_) async => throw UnimplementedError(),
            ),
      );
      final session = _personalSession();

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session),
        session,
      );

      expect(handled, isTrue);
      expect(harness.runtime.started, isTrue);
      expect(harness.runtime.executable, '/remote/bin/claude');
      expect(harness.runtime.sessionToolDir, '/remote/cfg/s1');
      expect(harness.runtime.baseEnv['PATH'], '/remote/bin');
      expect(harness.runtime.baseEnv['CLAUDE_CONFIG_DIR'], '/remote/cfg/s1');
    },
  );

  test('attachMemberAcpRuntime keeps a remote (ssh) member on the terminal',
      () async {
    final harness = _Harness();
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team-1',
      members: [
        SessionMemberBinding(
          rosterMemberId: 'lead',
          taskId: 'task-lead',
          cli: CliTool.claude,
          acp: true,
        ),
      ],
      memberTargets: const {'lead': 'ssh:p1'},
      createdAt: 1,
    );
    final team = _mixedTeam();
    final member = _lead();

    final handled = await harness.service.attachMemberAcpRuntime(
      _job(session, team, member),
      session,
      (team: team, member: member, cli: CliTool.claude),
    );

    expect(handled, isFalse);
    expect(harness.tab.memberAcpRuntimes, isEmpty);
    expect(harness.runtime.started, isFalse);
  });
}

class _Harness {
  _Harness({
    this.extra = const {
      'teammate-bus': {'type': 'http', 'url': 'http://127.0.0.1:9/mcp'},
    },
    this.gate,
    RuntimeTarget? launchTarget,
    this.remoteStaging,
    this.sshLaunchFactory,
  }) : launchTarget = launchTarget ?? RuntimeTarget.local() {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    materializer = _RecordingMaterializer(tabStore: tabStore);
    service = SessionLaunchService(
      _Host(tabStore, materializer, this.launchTarget),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) => runtime,
      prepareAcpContribution: (session, workspace) async => const {},
      prepareAcpTeamConnect:
          ({
            required session,
            required team,
            required member,
            required workspace,
            required launchTarget,
            required workingDirectory,
            extraMcpServers,
          }) async {
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'ACP_TEAM_STAGING': 'mixed-lead'},
                  resume: false,
                  taskId: member.id,
                  cliTeamName: team.name,
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: team,
                  member: member,
                  workingDirectory: workingDirectory,
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      acpMemberExtraMcp: ({required session, required member}) => extra,
      acpMemberLifecycleGate: gate,
      prepareAcpRemoteStaging: remoteStaging,
      prepareAcpSshLaunch: sshLaunchFactory,
    );
  }

  final Map<String, Map<String, Object?>> extra;
  final AcpMemberLifecycleGate? gate;
  final RuntimeTarget launchTarget;
  final AcpRemoteStagingBuilder? remoteStaging;
  final AcpSshLaunchFactory? sshLaunchFactory;
  final runtime = _RecordingAcpRuntime();
  late final _RecordingMaterializer materializer;
  final tabStore = ChatTabStore(storage: fakeHomeStorage());
  final tab = ChatTab(
    info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
    cliTeamName: '',
  );
  late final SessionLaunchService service;
}

TeamProfile _mixedTeam() => const TeamProfile(
  id: 'team-1',
  name: 'Team',
  teamMode: TeamMode.mixed,
  members: [TeamMemberConfig(id: 'lead', name: 'Lead')],
);

TeamMemberConfig _lead() =>
    const TeamMemberConfig(id: 'lead', name: 'Lead', cli: CliTool.claude);

AppSession _mixedSession({
  required bool acp,
  LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
}) => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  sessionTeam: 'team-1',
  members: [
    SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 'task-lead',
      cli: CliTool.claude,
      acp: acp,
      acpPermission: acpPermission,
    ),
  ],
  memberTargets: const {'lead': 'local'},
  createdAt: 1,
);

AppSession _personalSession({
  LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
}) => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  cli: CliTool.claude,
  acp: true,
  acpPermission: acpPermission,
  createdAt: 1,
);

SessionConnectJob _personalJob(AppSession session) {
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  return SessionConnectJob(
    session: session,
    request: SessionOpenRequest(session: session, workspace: workspace),
    generation: 1,
    workspace: workspace,
    reason: LaunchReason.create,
  );
}

SessionConnectJob _job(
  AppSession session,
  TeamProfile team,
  TeamMemberConfig member,
) {
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  return SessionConnectJob(
    session: session,
    request: SessionOpenRequest(
      session: session,
      workspace: workspace,
      team: team,
      member: member,
    ),
    generation: 1,
    workspace: workspace,
    team: team,
    member: member,
    reason: LaunchReason.create,
  );
}

class _FakeLifecycle implements SessionLifecycleService {
  _FakeLifecycle(this._target);

  final RuntimeTarget _target;

  @override
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => _target;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore, this.memberMaterializer, this._launchTarget);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  final RuntimeTarget _launchTarget;

  @override
  SessionLifecycleService get lifecycle => _FakeLifecycle(_launchTarget);

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
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _NoopConnector implements MemberConnector {
  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    String sessionId, {
    bool selectMember = true,
  }) {}
}

class _RecordingMaterializer extends TabMemberMaterializer {
  _RecordingMaterializer({required ChatTabStore tabStore})
    : super(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: tabStore,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => null,
          isClosed: () => false,
        ),
        tabStore: tabStore,
        connector: _NoopConnector(),
        activeTeam: () => null,
        isClosed: () => false,
        isMixedBusRegistered: (_) => true,
        isMemberConnectOwnedElsewhere: (_, __) => false,
      );

  final ready = <(String, String)>[];

  @override
  void markMemberReady(String sessionId, String memberId) {
    ready.add((sessionId, memberId));
    super.markMemberReady(sessionId, memberId);
  }
}

class _RecordingAcpRuntime implements AcpSessionRuntimeApi {
  var started = false;
  String? executable;
  String? sessionToolDir;
  Map<String, String> baseEnv = const {};
  List<acpd.McpServer> mcpServers = const [];
  LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess;
  void Function()? onStart;
  Completer<void>? startHold;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
  }) async {
    onStart?.call();
    final hold = startHold;
    if (hold != null) await hold.future;
    started = true;
    this.executable = executable;
    this.sessionToolDir = sessionToolDir;
    this.baseEnv = baseEnv;
    this.mcpServers = mcpServers;
    this.permissionPolicy = permissionPolicy;
  }

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {
    permissionPolicy = policy;
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
