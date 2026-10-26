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
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_files.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/agent_status/agent_status_seat_lookup_port.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
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
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_gateway_port.dart';
import 'package:teampilot/services/chat/team_bus/team_bus.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/opencode/capabilities/acp.dart'
    show opencodeEnableQuestionToolEnvKey;
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
      var sshLaunchBuilt = false;
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
            ({required session, required launchTarget}) {
              sshLaunchBuilt = true;
              return (
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
              );
            },
      );
      final session = _personalSession();

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session),
        session,
      );

      expect(handled, isTrue);
      expect(sshLaunchBuilt, isTrue);
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

  test(
    'attachAcpRuntime wires the question bridge for a local personal seat',
    () async {
      final gateway = _FakeAgentStatusGateway();
      final lookup = _FakeSeatLookup();
      final harness = _Harness(gateway: gateway, seatLookup: lookup);
      final session = _personalSession(cli: CliTool.opencode);

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session),
        session,
      );

      expect(handled, isTrue);
      expect(gateway.ensureStartedCalls, 1);
      expect(gateway.registeredSessions, ['s1']);
      expect(lookup.registeredSeats.single.sessionId, 's1');
      expect(lookup.registeredSeats.single.memberId, 's1');
      expect(lookup.registeredSeats.single.cli, CliTool.opencode);
      expect(
        harness.runtime.baseEnv[opencodeEnableQuestionToolEnvKey],
        'true',
      );
    },
  );

  test(
    'attachAcpRuntime stages app-owned MCP (catalog + session SSH) for a '
    'personal seat',
    () async {
      final gateway = _FakeAgentStatusGateway();
      final harness = _Harness(gateway: gateway);
      final session = _personalSession(cli: CliTool.opencode);
      final workspace = Workspace(
        workspaceId: 'w1',
        createdAt: 1,
        folders: const [
          WorkspaceFolder(
            path: '/local',
            targetId: WorkspaceFolder.localTargetId,
          ),
          WorkspaceFolder(path: '/home', targetId: 'ssh:home'),
        ],
      );

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session, workspace: workspace),
        session,
      );

      expect(handled, isTrue);
      final names = harness.runtime.mcpServers.map((s) => s.name).toSet();
      expect(names, contains('teampilot'));
      expect(names, contains('ssh'));
    },
  );

  test(
    'attachAcpRuntime keeps the question tool off when no responder is wired',
    () async {
      final harness = _Harness();
      final session = _personalSession(cli: CliTool.opencode);

      await harness.service.attachAcpRuntime(_personalJob(session), session);

      expect(
        harness.runtime.baseEnv.containsKey(opencodeEnableQuestionToolEnvKey),
        isFalse,
      );
    },
  );

  test(
    'attachAcpRuntime skips the question bridge for a remote seat',
    () async {
      final gateway = _FakeAgentStatusGateway();
      final harness = _Harness(
        gateway: gateway,
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        remoteStaging:
            ({
              required session,
              required workspace,
              required launchTarget,
            }) async => (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'PATH': '/remote/bin'},
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/remote/cfg/s1',
                  resolvedRoots: const [],
                ),
                launchContext: const CliLaunchContext(
                  team: TeamProfile(id: 't', name: 't'),
                  member: TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '/remote/bin/claude',
            ),
        sshLaunchFactory: ({required session, required launchTarget}) => (
          profile: const SshProfile(
            id: 'p1',
            name: 'host',
            host: 'host',
            username: 'u',
            authType: SshAuthType.password,
          ),
          openChannel: (_) async => throw UnimplementedError(),
        ),
      );
      final session = _personalSession(cli: CliTool.opencode);

      await harness.service.attachAcpRuntime(_personalJob(session), session);

      expect(gateway.ensureStartedCalls, 0);
      expect(gateway.registeredSessions, isEmpty);
      expect(
        harness.runtime.baseEnv.containsKey(opencodeEnableQuestionToolEnvKey),
        isFalse,
      );
    },
  );

  test(
    'attachMemberAcpRuntime forwards a question-only endpoint to staging',
    () async {
      final gateway = _FakeAgentStatusGateway();
      final lookup = _FakeSeatLookup();
      MemberAgentStatusEndpoint? seen;
      final harness = _Harness(
        gateway: gateway,
        seatLookup: lookup,
        onTeamAgentStatus: (endpoint) => seen = endpoint,
      );
      final session = _mixedSession(acp: true);
      final team = _mixedTeam();
      final member = _lead();

      final handled = await harness.service.attachMemberAcpRuntime(
        _job(session, team, member),
        session,
        (team: team, member: member, cli: CliTool.opencode),
      );

      expect(handled, isTrue);
      expect(gateway.ensureStartedCalls, 1);
      expect(gateway.registeredSessions, ['s1']);
      expect(lookup.registeredSeats.single.sessionId, 's1');
      expect(lookup.registeredSeats.single.memberId, 'lead');
      expect(lookup.registeredSeats.single.cli, CliTool.opencode);
      expect(seen, isNotNull);
      expect(seen!.questionsOnly, isTrue);
      expect(seen!.sessionId, 's1');
      expect(
        harness.runtime.baseEnv[opencodeEnableQuestionToolEnvKey],
        'true',
      );
    },
  );
}

class _FakeAgentStatusGateway implements TeammateBusMcpGatewayPort {
  int ensureStartedCalls = 0;
  final registeredSessions = <String>[];

  @override
  Future<void> ensureStarted() async {
    ensureStartedCalls++;
  }

  @override
  Uri get agentStatusEndpoint => Uri.parse('http://127.0.0.1:9/agent-status');

  @override
  Uri get mcpEndpoint => Uri.parse('http://127.0.0.1:9/mcp');

  @override
  Uri get catalogMcpEndpoint => Uri.parse('http://127.0.0.1:9/catalog/mcp');

  @override
  Uri get teamComposerMcpEndpoint =>
      Uri.parse('http://127.0.0.1:9/team-composer/mcp');

  @override
  Uri get sessionSshMcpEndpoint => Uri.parse('http://127.0.0.1:9/ssh/mcp');

  @override
  Uri get idleEndpoint => Uri.parse('http://127.0.0.1:9/idle');

  @override
  int get httpPort => 9;

  @override
  int get rawSocketPort => 10;

  @override
  String registerAgentStatusSession({
    required String sessionId,
    String? token,
  }) {
    registeredSessions.add(sessionId);
    return 'status-token-$sessionId';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSeatLookup implements AgentStatusSeatLookupPort {
  final registeredSeats =
      <
        ({
          String sessionId,
          String memberId,
          CliTool cli,
          bool skipPermissions,
        })
      >[];

  @override
  void registerSeat({
    required String sessionId,
    required String memberId,
    required CliTool cli,
    required bool skipPermissions,
  }) {
    registeredSeats.add((
      sessionId: sessionId,
      memberId: memberId,
      cli: cli,
      skipPermissions: skipPermissions,
    ));
  }

  @override
  void unregisterSeat({required String sessionId, required String memberId}) {}

  @override
  void clearSession(String sessionId) {}
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
    this.gateway,
    this.seatLookup,
    this.onTeamAgentStatus,
  }) : launchTarget = launchTarget ?? RuntimeTarget.local() {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    materializer = _RecordingMaterializer(tabStore: tabStore);
    service = SessionLaunchService(
      _Host(
        tabStore,
        materializer,
        this.launchTarget,
        gateway: gateway,
        seatLookup: seatLookup,
      ),
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
            agentStatus,
          }) async {
            onTeamAgentStatus?.call(agentStatus);
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
  final TeammateBusMcpGatewayPort? gateway;
  final AgentStatusSeatLookupPort? seatLookup;
  final void Function(MemberAgentStatusEndpoint? endpoint)? onTeamAgentStatus;
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
  CliTool cli = CliTool.claude,
}) => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  cli: cli,
  acp: true,
  acpPermission: acpPermission,
  createdAt: 1,
);

SessionConnectJob _personalJob(AppSession session, {Workspace? workspace}) {
  final resolved = workspace ?? Workspace(workspaceId: 'w1', createdAt: 1);
  return SessionConnectJob(
    session: session,
    request: SessionOpenRequest(session: session, workspace: resolved),
    generation: 1,
    workspace: resolved,
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
  _Host(
    this.tabStore,
    this.memberMaterializer,
    this._launchTarget, {
    this.gateway,
    this.seatLookup,
  });

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  final RuntimeTarget _launchTarget;

  final TeammateBusMcpGatewayPort? gateway;

  @override
  TeammateBusMcpGatewayPort get teammateBusMcpGateway =>
      gateway ??
      (throw UnsupportedError('teammateBusMcpGateway not configured in test'));

  @override
  AgentStatusSeatLookupPort? get agentStatusSeatLookup => seatLookup;

  final AgentStatusSeatLookupPort? seatLookup;

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
    String? resumeSessionId,
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
