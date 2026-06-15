@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  Future<Set<String>> namesIn(String dir) async {
    final entries = await AppStorage.fs.listDir(dir);
    return entries.map((e) => e.name).toSet();
  }

  test('the same enabled skill lands identically in personal, native, and mixed modes',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);

    // Install a skill source directory into the global skills library.
    await fs.ensureDir(
      fs.pathContext.join(AppPaths.skillsDirForTeampilotRoot(root), 'demo-skill'),
    );

    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
      loadInstalledSkills: () async => [
        const Skill(
          id: 'demo',
          name: 'Demo',
          description: '',
          directory: 'demo-skill',
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );

    // ── personal mode ──────────────────────────────────────────────────────
    await service.prepareProjectLaunch(
      projectId: 'p',
      sessionId: 's',
      profile: const ProjectProfile(
        projectId: 'p',
        // TODO: migrate to presets — cli removed
        skillIds: ['demo'],
      ),
    );

    // ── native team mode ───────────────────────────────────────────────────
    await service.prepareTeamLaunch(
      teamId: 'tn',
      runtimeTeamId: 'tn-1',
      cli: CliTool.flashskyai,
      team: const TeamConfig(
        id: 'tn',
        name: 'TN',
        cli: CliTool.flashskyai,
        skillIds: ['demo'],
      ),
    );

    // ── mixed team mode ────────────────────────────────────────────────────
    // For a mixed team the per-member leaf is nested under
    //   memberToolDir(teamId, mixedModeMemberScopeSessionId(sessionId, member), tool)
    // We must pass a member so prepareTeamLaunch produces the nested path.
    const mixedMember = TeamMemberConfig(id: 'm1', name: 'M1');
    await service.prepareTeamLaunch(
      teamId: 'tm',
      runtimeTeamId: 'tm-1',
      cli: CliTool.flashskyai,
      member: mixedMember,
      team: const TeamConfig(
        id: 'tm',
        name: 'TM',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.mixed,
        skillIds: ['demo'],
      ),
    );

    // ── assert personal ────────────────────────────────────────────────────
    final personal = await namesIn(
      fs.pathContext.join(
        layout.standaloneProjectSessionToolDir('p', 's', 'flashskyai'),
        'skills',
      ),
    );

    // ── assert native ──────────────────────────────────────────────────────
    final native = await namesIn(
      fs.pathContext.join(
        layout.memberToolDir('tn', 'tn-1', 'flashskyai'),
        'skills',
      ),
    );

    // ── assert mixed ───────────────────────────────────────────────────────
    // Compute the nested sessionId the same way prepareTeamLaunch does.
    final mixedSessionId = mixedModeMemberScopeSessionId(
      fs.pathContext,
      'tm-1',
      mixedMember,
    );
    // The safe segment applied to 'm1' is 'm1' (all alphanumeric-plus-dash).
    final expectedMixedSessionId = fs.pathContext.join(
      'tm-1',
      ClaudeTeamRosterService.safeClaudePathSegment('m1'),
    );
    expect(mixedSessionId, expectedMixedSessionId,
        reason: 'sanity-check: mixed session-id path construction agrees');

    final mixed = await namesIn(
      fs.pathContext.join(
        layout.memberToolDir('tm', mixedSessionId, 'flashskyai'),
        'skills',
      ),
    );

    expect(personal, contains('demo-skill'),
        reason: 'personal mode must provision the enabled skill');
    expect(native, contains('demo-skill'),
        reason: 'native team mode must provision the enabled skill');
    expect(mixed, contains('demo-skill'),
        reason: 'mixed team mode must provision the enabled skill per-member');

    // All three sets must be equal — same skill, same directory name.
    expect(personal, equals(native),
        reason: 'personal and native must provision the same set of skills');
    expect(personal, equals(mixed),
        reason: 'personal and mixed must provision the same set of skills');
  });
}
