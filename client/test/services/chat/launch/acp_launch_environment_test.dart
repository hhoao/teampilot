import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/chat/launch/connect/acp_launch_environment.dart';
import 'package:teampilot/services/chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/chat/launch/session/shell_launch_spec.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  test('merges PATH with contributeLaunch env from simple connect', () async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.claude,
      acp: true,
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
    AppSession? seenSession;
    Workspace? seenWorkspace;

    final env = await prepareAcpLaunchEnvironment(
      prepareSimpleConnect:
          ({
            required session,
            required workspace,
            required launchTarget,
            extraMcpServers,
            agentStatus,
          }) async {
            seenSession = session;
            seenWorkspace = workspace;
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {
                    'CLAUDE_CONFIG_DIR': '/runtime/s1/claude',
                    'CLAUDE_CODE_NO_FLICKER': '1',
                  },
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: const CliLaunchContext(
                  team: TeamProfile(id: 't', name: 't'),
                  member: TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>['claude_credentials_missing'],
              remoteCliPath: '',
            );
          },
      session: session,
      workspace: workspace,
      launchTarget: RuntimeTarget.local(),
      path: '/usr/bin',
    );

    expect(seenSession, same(session));
    expect(seenWorkspace, same(workspace));
    expect(env['PATH'], '/usr/bin');
    expect(env['CLAUDE_CONFIG_DIR'], '/runtime/s1/claude');
    expect(env['CLAUDE_CODE_NO_FLICKER'], '1');
  });

  test('forwards the ACP agent-status endpoint to simple connect', () async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.claude,
      acp: true,
      createdAt: 1,
    );
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:9/agent-status',
      sessionId: 's1',
      questionsOnly: true,
    );
    MemberAgentStatusEndpoint? seen;

    await prepareAcpLaunchEnvironment(
      prepareSimpleConnect:
          ({
            required session,
            required workspace,
            required launchTarget,
            extraMcpServers,
            agentStatus,
          }) async {
            seen = agentStatus;
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {},
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: const CliLaunchContext(
                  team: TeamProfile(id: 't', name: 't'),
                  member: TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      session: session,
      workspace: Workspace(workspaceId: 'w1', createdAt: 1),
      launchTarget: RuntimeTarget.local(),
      agentStatus: endpoint,
    );

    expect(seen, same(endpoint));
  });

  test('forwards extra MCP servers to simple connect', () async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      cli: CliTool.opencode,
      acp: true,
      createdAt: 1,
    );
    Map<String, Map<String, Object?>>? seenExtra;

    await prepareAcpLaunchEnvironment(
      prepareSimpleConnect:
          ({
            required session,
            required workspace,
            required launchTarget,
            extraMcpServers,
            agentStatus,
          }) async {
            seenExtra = extraMcpServers;
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'OPENCODE_CONFIG_DIR': '/runtime/s1/opencode'},
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/runtime/s1/opencode',
                  resolvedRoots: const [],
                ),
                launchContext: const CliLaunchContext(
                  team: TeamProfile(id: 't', name: 't'),
                  member: TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      session: session,
      workspace: Workspace(workspaceId: 'w1', createdAt: 1),
      launchTarget: RuntimeTarget.local(),
      extraMcpServers: const {
        'ssh': {'type': 'http', 'url': 'http://127.0.0.1:9/ssh/mcp'},
      },
    );

    expect(seenExtra?.containsKey('ssh'), isTrue);
  });

  test('team prepare merges PATH with team connect env and maps MCP', () async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
    const team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      teamMode: TeamMode.mixed,
    );
    const member = TeamMemberConfig(id: 'lead', name: 'Lead');
    Map<String, Map<String, Object?>>? seenExtra;

    final staged = await prepareAcpTeamLaunchEnvironment(
      prepareTeamConnect:
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
            seenExtra = extraMcpServers;
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'ACP_TEAM_STAGING': 'mixed-lead'},
                  resume: false,
                  taskId: 'lead',
                  cliTeamName: 'team-1',
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: team,
                  member: member,
                  workingDirectory: '/from-team-prepare',
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      session: session,
      team: team,
      member: member,
      workspace: workspace,
      launchTarget: RuntimeTarget.local(),
      workingDirectory: '/session/folder',
      extraMcpServers: const {
        teammateBusMcpServerName: {
          'type': 'http',
          'url': 'http://127.0.0.1:9/mcp',
        },
      },
      path: '/usr/bin',
    );

    expect(seenExtra?.containsKey(teammateBusMcpServerName), isTrue);
    expect(staged.env['PATH'], '/usr/bin');
    expect(staged.env['ACP_TEAM_STAGING'], 'mixed-lead');
    expect(staged.workingDirectory, '/from-team-prepare');
    expect(
      (staged.mcpServers.single as acpd.McpServerHttp).name,
      teammateBusMcpServerName,
    );
  });

  test('team prepare throws when teammate-bus does not map', () async {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    const team = TeamProfile(id: 'team-1', name: 'Team');
    const member = TeamMemberConfig(id: 'lead', name: 'Lead');

    await expectLater(
      prepareAcpTeamLaunchEnvironment(
        prepareTeamConnect:
            ({
              required session,
              required team,
              required member,
              required workspace,
              required launchTarget,
              required workingDirectory,
              extraMcpServers,
              agentStatus,
            }) async =>
                throw StateError('prepare should not run'),        session: session,
        team: team,
        member: member,
        workspace: Workspace(workspaceId: 'w1', createdAt: 1),
        launchTarget: RuntimeTarget.local(),
        workingDirectory: '',
        extraMcpServers: const {
          teammateBusMcpServerName: {'type': 'http'},
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'ACP teammate-bus MCP did not map to a session server',
        ),
      ),
    );
  });

  test('selectAcpRemoteLaunch keeps the work-plane env and remote paths', () {
    final prepared = (
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
        launchContext: const CliLaunchContext(
          team: TeamProfile(id: 't', name: 't'),
          member: TeamMemberConfig(id: 's1', name: 's1'),
        ),
      ),
      warnings: const <String>[],
      remoteCliPath: '/remote/bin/opencode',
    );

    final selected = selectAcpRemoteLaunch(
      prepared: prepared,
      localExecutable: '/usr/bin/opencode',
      localSessionToolDir: '/home/u/.local/share/tp/s1/opencode',
    );

    expect(selected.executable, '/remote/bin/opencode');
    expect(selected.sessionToolDir, '/remote/cfg/s1');
    expect(selected.env['PATH'], '/remote/bin');
    expect(selected.env['CLAUDE_CONFIG_DIR'], '/remote/cfg/s1');
  });

  test('selectAcpRemoteLaunch falls back to local values when remote is empty',
      () {
    final prepared = (
      shellLaunch: ShellLaunchSpec(
        plan: LaunchPlan(
          env: const {'PATH': '/remote/bin'},
          resume: false,
          taskId: 's1',
          cliTeamName: '',
          memberConfigDir: '',
          resolvedRoots: const [],
        ),
        launchContext: const CliLaunchContext(
          team: TeamProfile(id: 't', name: 't'),
          member: TeamMemberConfig(id: 's1', name: 's1'),
        ),
      ),
      warnings: const <String>[],
      remoteCliPath: '',
    );

    final selected = selectAcpRemoteLaunch(
      prepared: prepared,
      localExecutable: '/usr/bin/opencode',
      localSessionToolDir: '/home/u/.local/share/tp/s1/opencode',
    );

    expect(selected.executable, '/usr/bin/opencode');
    expect(selected.sessionToolDir, '/home/u/.local/share/tp/s1/opencode');
    expect(selected.env['PATH'], '/remote/bin');
  });
}
