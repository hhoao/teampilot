@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

/// Regression lock for the staging-layer pollution bug: the leaf CONFIG_DIR's
/// `skills/` must be a REAL directory owned by ResourceProvisioningService, NOT
/// a symlink inherited from the project/team staging layer. On symlink-capable
/// platforms the old inherit-then-materialize path made `skills/` a symlink into
/// the shared staging layer, so the materializer wrote through it (polluting and
/// clobbering across sessions). These assertions fail on that old behavior.
void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  ConfigProfileService buildService(String root, CliDataLayout layout) =>
      ConfigProfileService(
        basePath: root,
        fs: AppStorage.fs,
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

  test('personal leaf skills/ is a real directory, not a staging symlink',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);
    await fs.ensureDir(
      fs.pathContext.join(AppPaths.skillsDirForTeampilotRoot(root), 'demo-skill'),
    );

    await buildService(root, layout).prepareProjectLaunch(
      projectId: 'p',
      sessionId: 's',
      profile: const ProjectProfile(
        projectId: 'p',
        // TODO: migrate to presets — cli removed
        skillIds: ['demo'],
      ),
    );

    final leafSkills = fs.pathContext.join(
      layout.standaloneProjectSessionToolDir('p', 's', 'flashskyai'),
      'skills',
    );
    final stat = await fs.stat(leafSkills);
    expect(stat.isSymlink, isFalse,
        reason: 'leaf skills/ must be a real directory owned by the materializer');
    expect((await fs.listDir(leafSkills)).map((e) => e.name),
        contains('demo-skill'));
  });

  test('team member leaf skills/ is a real directory, not a staging symlink',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);
    await fs.ensureDir(
      fs.pathContext.join(AppPaths.skillsDirForTeampilotRoot(root), 'demo-skill'),
    );

    await buildService(root, layout).prepareTeamLaunch(
      teamId: 't',
      runtimeTeamId: 't-1',
      cli: CliTool.flashskyai,
      team: const TeamConfig(
        id: 't',
        name: 'T',
        cli: CliTool.flashskyai,
        skillIds: ['demo'],
      ),
    );

    final leafSkills = fs.pathContext.join(
      layout.memberToolDir('t', 't-1', 'flashskyai'),
      'skills',
    );
    final stat = await fs.stat(leafSkills);
    expect(stat.isSymlink, isFalse,
        reason: 'member leaf skills/ must be a real directory owned by the materializer');
    expect((await fs.listDir(leafSkills)).map((e) => e.name),
        contains('demo-skill'));
  });
}
