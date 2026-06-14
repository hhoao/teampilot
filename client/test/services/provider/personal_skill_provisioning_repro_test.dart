@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';

import '../../support/post_frame_test_harness.dart';

/// RED repro: enabled skills are NOT materialized into the personal-mode
/// session leaf CONFIG_DIR at launch.  This test must remain failing until
/// the provisioning fix is implemented.
void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  test(
    'enabled skill is materialized into personal-mode leaf CONFIG_DIR/skills/',
    () async {
      final root = AppStorage.paths.basePath;
      final fs = AppStorage.fs;
      final layout = CliDataLayout(teampilotRoot: root, fs: fs);

      // --- Arrange: install a skill into the global library ---
      final skillsRoot = AppPaths.skillsDirForTeampilotRoot(root);
      final skillDir = p.join(skillsRoot, 'demo-skill');
      await Directory(skillDir).create(recursive: true);
      await File(p.join(skillDir, 'SKILL.md')).writeAsString('# demo-skill');

      // --- Construct the service (current API — no loadInstalledSkills param) ---
      final service = ConfigProfileService(
        basePath: root,
        fs: fs,
        layout: layout,
        hostEnvironment: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ),
      );

      // --- Profile with skill 'demo' enabled ---
      const profile = ProjectProfile(
        projectId: 'p1',
        cli: CliTool.flashskyai,
        skillIds: ['demo'],
      );

      // --- Act: run personal-mode launch prep ---
      await service.prepareProjectLaunch(
        projectId: 'p1',
        sessionId: 's1',
        profile: profile,
      );

      // --- Assert: the leaf CONFIG_DIR/skills/ must contain demo-skill ---
      final leafToolDir =
          layout.standaloneProjectSessionToolDir('p1', 's1', 'flashskyai');
      final skillsLeafDir = p.join(leafToolDir, 'skills');
      final entries = await fs.listDir(skillsLeafDir);

      expect(
        entries.map((e) => e.name),
        contains('demo-skill'),
        reason:
            'enabled skill must be materialized into the leaf CONFIG_DIR/skills/ '
            'but the skills provisioning path is not wired up for personal mode',
      );
    },
  );
}
