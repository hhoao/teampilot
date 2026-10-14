import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
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
}

class _Harness {
  _Harness({
    this.extra = const {
      'teammate-bus': {'type': 'http', 'url': 'http://127.0.0.1:9/mcp'},
    },
    this.gate,
  }) {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    materializer = _RecordingMaterializer(tabStore: tabStore);
    service = SessionLaunchService(
      _Host(tabStore, materializer),
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
    );
  }

  final Map<String, Map<String, Object?>> extra;
  final AcpMemberLifecycleGate? gate;
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

class _Host implements SessionLaunchHost {
  _Host(this.tabStore, this.memberMaterializer);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

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
