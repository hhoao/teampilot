import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/workspace_agent_config.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/cli/registry/config_profile/cursor_config_profile_capability.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import '../../../support/in_memory_filesystem.dart';

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
    final cursorDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      CursorConfigProfileCapability.toolId,
      memberId: scope.memberId,
    );
    return paths.pathContext.join(cursorDir, 'home');
  }

  group('CursorConfigProfileCapability', () {
    test('standalone HOME-isolates with CURSOR_CONFIG_DIR at .cursor', () async {
      const team = TeamProfile(id: 'team-a', name: 'agent', cli: CliTool.cursor);
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );
      const profile = PersonalProfile(id: 'workspace-1', display: 'workspace-1',
        agent: WorkspaceAgentConfig(agent: 'solo'),
      );
      const standalone = StandaloneLaunchProfileScope(
        workspaceId: 'workspace-1',
        sessionId: 'session-1',
      );

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
          standaloneScope: standalone,
          personal: profile,
        ),
      );

      final env = contribution.environment;
      final home = env['HOME']!;
      expect(env['USERPROFILE'], home);
      expect(home, endsWith('${paths.pathContext.separator}home'));
      expect(env['CURSOR_CONFIG_DIR'], paths.pathContext.join(home, '.cursor'));
      expect(contribution.warnings, isEmpty);
    });

    test('standalone pre-provisions workspace trust under isolated home', () async {
      const workspace = '/home/hhoa/git/hhoa/teampilot';
      const profile = PersonalProfile(id: 'workspace-1', display: 'workspace-1',
        agent: WorkspaceAgentConfig(agent: 'solo'),
      );
      const standalone = StandaloneLaunchProfileScope(
        workspaceId: 'workspace-1',
        sessionId: 'session-1',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'workspace-1',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );

      final contribution = await capability.contributeLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: '',
          sessionId: 'session-1',
          scope: scope,
          personal: profile,
          members: const [],
          paths: paths,
          standaloneScope: standalone,
          workingDirectory: workspace,
        ),
      );

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        contribution.environment['HOME']!,
        workspace,
        pathContext: fs.pathContext,
      );
      expect((await fs.stat(trustPath)).isFile, isTrue);
    });

    test('mixed pre-provisions workspace trust under member home', () async {
      const team = TeamProfile(
        id: 'team-a',
        name: 'agent',
        cli: CliTool.cursor,
        teamMode: TeamMode.mixed,
      );
      final scope = mixedScope();
      const workspace = '/home/hhoa/Document/testmixed';

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
          busIdleUrl: 'http://127.0.0.1:5050/idle',
          workingDirectory: workspace,
        ),
      );

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        memberHome(scope),
        workspace,
        pathContext: fs.pathContext,
      );
      expect((await fs.stat(trustPath)).isFile, isTrue);
    });

    test('mixed contributes HOME and not CURSOR_CONFIG_DIR or plugin dir key',
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
          busIdleUrl: 'http://127.0.0.1:5050/idle',
        ),
      );

      final home = memberHome(scope);
      expect(contribution.environment['HOME'], home);
      expect(contribution.environment['USERPROFILE'], home);
      expect(contribution.environment, isNot(contains('CURSOR_CONFIG_DIR')));
      expect(contribution.environment.keys, isNot(contains(startsWith('TEAMPILOT_'))));
    });

    test('mixed warns when provider, credentials, and bus port are missing',
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
        ),
      );

      expect(contribution.warnings, contains('cursor_provider_missing'));
      expect(contribution.warnings, contains('cursor_bus_idle_url_missing'));
    });

    test('mixed warns cursor_credentials_missing when provider not ready',
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
          busIdleUrl: 'http://127.0.0.1:5050/idle',
        ),
      );

      expect(contribution.warnings, isNot(contains('cursor_provider_missing')));
      expect(contribution.warnings, contains('cursor_credentials_missing'));
    });

    test('mixed provisions bus overlay under member home when port set', () async {
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
          busIdleUrl: 'http://127.0.0.1:4321/idle',
        ),
      );

      expect((await fs.stat(layout.roleRule(home))).isFile, isTrue);
      expect((await fs.stat(layout.mcpConfig(home))).isFile, isTrue);
      expect((await fs.stat(layout.hooksConfig(home))).isFile, isTrue);
      expect((await fs.stat(layout.idleScript(home))).isFile, isTrue);
    });
  });
}
