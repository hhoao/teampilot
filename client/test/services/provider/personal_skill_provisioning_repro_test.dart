@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';

import '../../support/post_frame_test_harness.dart';

/// Repro (now GREEN): enabled skills ARE materialized into the personal-mode
/// session leaf CONFIG_DIR at launch via ResourceProvisioningService.
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
      final layout = RuntimeLayout(teampilotRoot: root, fs: fs);

      // --- Arrange: install a skill into the global library ---
      final skillsRoot = AppPaths.skillsDirForTeampilotRoot(root);
      final skillDir = p.join(skillsRoot, 'demo-skill');
      await Directory(skillDir).create(recursive: true);
      await File(p.join(skillDir, 'SKILL.md')).writeAsString('# demo-skill');

      // --- Construct the service with loadInstalledSkills injected ---
      final service = ConfigProfileService(
        basePath: root,
        fs: fs,
        layout: layout,
        hostEnvironment: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ),
        loadInstalledSkills: () async => [
          Skill(
            id: 'demo',
            name: 'Demo',
            description: '',
            directory: 'demo-skill',
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
      );

      // --- Profile with skill 'demo' enabled ---
      const profile = PersonalProfile(id: 'p1', display: 'p1',
        // TODO: migrate to presets — cli removed
        bundle: ConfigBundle(skillIds: ['demo']),
      );

      // --- Act: run personal-mode launch prep ---
      await service.prepareWorkspaceLaunch(profileId: 'personal-default', 
        workspaceId: 'p1',
        sessionId: 's1',
        personal: profile,
      );

      // --- Assert: the leaf CONFIG_DIR/skills/ must contain demo-skill ---
      final leafToolDir =
          layout.sessionRuntimeToolDir('p1', 's1', 'flashskyai');
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

  test(
    'missing skill source dir produces a warning in TeamLaunchOutcome',
    () async {
      final root = AppStorage.paths.basePath;
      final fs = AppStorage.fs;
      final layout = RuntimeLayout(teampilotRoot: root, fs: fs);

      // --- Construct the service: skill 'ghost' references a non-existent dir ---
      final service = ConfigProfileService(
        basePath: root,
        fs: fs,
        layout: layout,
        hostEnvironment: HostExecutionEnvironment.resolve(
          isWindowsHost: false,
          storageMode: StorageBackendMode.native,
        ),
        loadInstalledSkills: () async => [
          Skill(
            id: 'ghost',
            name: 'Ghost',
            description: '',
            directory: 'missing-skill', // source directory intentionally absent
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
      );

      // --- Profile with skill 'ghost' enabled ---
      const profile = PersonalProfile(id: 'p2', display: 'p2',
        // TODO: migrate to presets — cli removed
        bundle: ConfigBundle(skillIds: ['ghost']),
      );

      // --- Act ---
      final outcome = await service.prepareWorkspaceLaunch(profileId: 'personal-default', 
        workspaceId: 'p2',
        sessionId: 's2',
        personal: profile,
      );

      // --- Assert: warning mentioning the missing skill id must surface ---
      expect(
        outcome.warnings,
        anyElement(contains('ghost')),
        reason:
            'a skill whose source directory is missing must produce a warning '
            'in the returned TeamLaunchOutcome.warnings',
      );
    },
  );
}
