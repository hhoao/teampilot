import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/chat/launch/connect/acp_launch_environment.dart';
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
}
