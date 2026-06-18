@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() { setUpTestAppStorage(); });
  tearDown(() { tearDownTestAppStorage(); });

  test('team launch prep links enabled skill into member leaf CONFIG_DIR', () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);

    final skillsRoot = AppPaths.skillsDirForTeampilotRoot(root);
    await fs.ensureDir(fs.pathContext.join(skillsRoot, 'demo-skill'));

    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
      loadInstalledSkills: () async => [
        Skill(id: 'demo', name: 'Demo', description: '', directory: 'demo-skill', installedAt: 0, updatedAt: 0),
      ],
    );

    const team = TeamIdentity(id: 't1', name: 'T1', cli: CliTool.flashskyai, skillIds: ['demo']);

    await service.prepareTeamLaunch(
      workspaceId: 'workspace-1',
      sessionId: 't1-1',
      teamId: 't1',
      cliTeamName: 't1-1',
      cli: CliTool.flashskyai,
      team: team,
    );

    final leafSkillsDir = fs.pathContext.join(
      layout.sessionRuntimeToolDir('workspace-1', 't1-1', 'flashskyai'),
      'skills',
    );
    final entries = await fs.listDir(leafSkillsDir);
    expect(entries.map((e) => e.name), contains('demo-skill'));
  });
}
