import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_agent_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/control_plane_profile_paths.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/cursor_config_profile_capability.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import '../../../support/in_memory_filesystem.dart';

RuntimeContext _memoryContext(String dir, InMemoryFilesystem fs) =>
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: dir,
      cwd: dir,
      appDataRoot: dir,
      paths: AppPaths(dir),
    );

void main() {
  const capability = CursorConfigProfileCapability();
  const base = '/data/tp';
  const member = TeamMemberConfig(
    id: 'planner',
    name: 'Planner',
    prompt: '只做代码审查',
  );

  late InMemoryFilesystem fs;
  late ConfigProfileService paths;
  late CursorHomeLayout layout;

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CursorHomeLayout(pathContext: fs.pathContext);
    paths = ConfigProfileService(
      basePath: base,
      home: '/fake/user/home',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base, fs: fs),
    );
  });

  LaunchProfileScope mixedScope() => resolveLaunchProfileScope(
    workspaceId: 'workspace-1',
    teamId: 'team-a',
    appSessionId: 'session-1',
    cliTeamName: 'session-1',
    memberId: ClaudeTeamRosterService.safeClaudePathSegment(member.id),
  );

  String memberHome(LaunchProfileScope scope) {
    final memberId = scope.memberId ?? '';
    final cursorDir = paths.layout.workspaceRuntimeMemberToolDir(
      scope.workspaceId,
      scope.teamId,
      memberId,
      CursorConfigProfileCapability.toolId,
    );
    return paths.pathContext.join(cursorDir, 'home');
  }

  group('CursorConfigProfileCapability', () {
    test('simple contributeLaunch writes role.mdc under fake HOME', () async {
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: '',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );
      final toolDir = paths.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        CursorConfigProfileCapability.toolId,
        memberId: scope.memberId,
      );
      final home = paths.pathContext.join(toolDir, 'home');

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: scope.sessionId,
          scope: scope,
          member: member,
          members: const [member],
          paths: paths,
          catalog: paths,
        ),
      );

      expect(contribution.environment['HOME'], home);
      final roleRule = await fs.readString(layout.roleRule(home));
      expect(roleRule, startsWith('---\nalwaysApply: true\n---\n'));
      expect(roleRule, contains('只做代码审查'));
    });

    test(
      'mixed contributeLaunch sets HOME without provisioning overlay files',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
        );
        final scope = mixedScope();
        final home = memberHome(scope);

        final contribution = await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: scope.teamId,
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: member,
            members: const [member],
            paths: paths,
            catalog: paths,
            busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:4321/idle'),
          ),
        );

        expect(contribution.environment['HOME'], home);
        expect((await fs.stat(layout.roleRule(home))).exists, isFalse);
      },
    );

    test(
      'mixed contributes HOME and not CURSOR_CONFIG_DIR or plugin dir key',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
        );
        final scope = mixedScope();

        final contribution = await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: scope.teamId,
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: member,
            members: const [member],
            paths: paths,
            catalog: paths,
            busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:5050/idle'),
          ),
        );

        final home = memberHome(scope);
        expect(contribution.environment['HOME'], home);
        expect(contribution.environment['USERPROFILE'], home);
        expect(contribution.environment, isNot(contains('CURSOR_CONFIG_DIR')));
        expect(
          contribution.environment.keys,
          isNot(contains(startsWith('TEAMPILOT_'))),
        );
      },
    );

    test(
      'mixed warns when provider, credentials, and bus port are missing',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
        );
        final scope = mixedScope();

        final contribution = await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: scope.teamId,
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: member,
            members: const [member],
            paths: paths,
            catalog: paths,
          ),
        );

        expect(contribution.warnings, contains('cursor_provider_missing'));
        expect(contribution.warnings, contains('cursor_bus_idle_missing'));
      },
    );

    test(
      'mixed warns cursor_credentials_missing when provider not ready',
      () async {
        final repository = AppProviderRepository(basePath: base, fs: fs);
        await repository.saveProviders(CliTool.cursor, [
          const AppProviderConfig(
            id: 'work',
            cli: CliTool.cursor,
            name: 'work',
            category: AppProviderCategory.thirdParty,
            config: {},
          ),
        ]);
        const team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          providerIdsByTool: {'cursor': 'work'},
        );
        final scope = mixedScope();

        final contribution = await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: scope.teamId,
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: member,
            members: const [member],
            paths: paths,
            catalog: paths,
            busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:5050/idle'),
          ),
        );

        expect(
          contribution.warnings,
          isNot(contains('cursor_provider_missing')),
        );
        expect(contribution.warnings, contains('cursor_credentials_missing'));
      },
    );

    test(
      'mixed overlay files are provisioned by session lifecycle, not contributeLaunch',
      () async {
        const team = TeamProfile(
          id: 'team-a',
          name: 'agent',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
        );
        final scope = mixedScope();
        final home = memberHome(scope);

        await capability.contributeLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: scope.teamId,
            sessionId: scope.sessionId,
            scope: scope,
            team: team,
            member: member,
            members: const [member],
            paths: paths,
            catalog: paths,
            busIdle: MemberBusIdleEndpoint(url: 'http://127.0.0.1:4321/idle'),
          ),
        );

        expect((await fs.stat(layout.roleRule(home))).exists, isFalse);
        expect((await fs.stat(layout.mcpConfig(home))).exists, isFalse);
      },
    );
  });
}
