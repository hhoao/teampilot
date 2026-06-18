@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_scope.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
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

  test(
    'the same enabled skill lands identically in personal, native, and mixed modes',
    () async {
      final fs = AppStorage.fs;
      final root = AppStorage.paths.basePath;
      final layout = RuntimeLayout(teampilotRoot: root, fs: fs);

      await fs.ensureDir(
        fs.pathContext.join(
          AppPaths.skillsDirForTeampilotRoot(root),
          'demo-skill',
        ),
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

      await service.prepareProjectLaunch(identityId: 'personal-default', 
        projectId: 'p',
        sessionId: 's',
        personal: const PersonalIdentity(id: 'p', display: 'p',
          bundle: ConfigBundle(skillIds: ['demo']),
        ),
      );

      await service.prepareTeamLaunch(
        projectId: 'project-1',
        sessionId: 'tn-1',
        teamId: 'tn',
        cliTeamName: 'tn-1',
        cli: CliTool.flashskyai,
        team: const TeamIdentity(
          id: 'tn',
          name: 'TN',
          cli: CliTool.flashskyai,
          skillIds: ['demo'],
        ),
      );

      const mixedMember = TeamMemberConfig(id: 'm1', name: 'M1');
      await service.prepareTeamLaunch(
        projectId: 'project-1',
        sessionId: 'tm-1',
        teamId: 'tm',
        cliTeamName: 'tm-1',
        cli: CliTool.flashskyai,
        member: mixedMember,
        team: const TeamIdentity(
          id: 'tm',
          name: 'TM',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.mixed,
          skillIds: ['demo'],
        ),
      );

      final personal = await namesIn(
        fs.pathContext.join(
          layout.sessionRuntimeToolDir('p', 's', 'flashskyai'),
          'skills',
        ),
      );

      final native = await namesIn(
        fs.pathContext.join(
          layout.sessionRuntimeToolDir('project-1', 'tn-1', 'flashskyai'),
          'skills',
        ),
      );

      final mixedSessionId = mixedModeMemberScopeSessionId(
        fs.pathContext,
        'tm-1',
        mixedMember,
      );
      final expectedMixedSessionId = fs.pathContext.join(
        'tm-1',
        ClaudeTeamRosterService.safeClaudePathSegment('m1'),
      );
      expect(
        mixedSessionId,
        expectedMixedSessionId,
        reason: 'sanity-check: mixed session-id path construction agrees',
      );

      final mixed = await namesIn(
        fs.pathContext.join(
          layout.sessionRuntimeToolDir(
            'project-1',
            'tm-1',
            'flashskyai',
            memberId: 'm1',
          ),
          'skills',
        ),
      );

      expect(
        personal,
        contains('demo-skill'),
        reason: 'personal mode must provision the enabled skill',
      );
      expect(
        native,
        contains('demo-skill'),
        reason: 'native team mode must provision the enabled skill',
      );
      expect(
        mixed,
        contains('demo-skill'),
        reason: 'mixed team mode must provision the enabled skill per-member',
      );

      expect(
        personal,
        equals(native),
        reason: 'personal and native must provision the same set of skills',
      );
      expect(
        personal,
        equals(mixed),
        reason: 'personal and mixed must provision the same set of skills',
      );
    },
  );
}
