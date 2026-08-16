import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-cubit-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SkillCubit cubitWith(SkillAcquisitionEngine engine) => SkillCubit(
    SkillRepository(),
    registryConfigService: SkillRegistryConfigService(
      teampilotRoot: AppStorage.paths.basePath,
    ),
    initialSources: const [],
    rebuildSources: (c) => const [],
    acquisitionEngine: engine,
  );

  test(
    'installTeamDependency uses scriptUrl sugar through acquisition engine',
    () async {
      const expectedId = 'script:custom/gstack';
      var engineCalls = 0;
      final engine = SkillAcquisitionEngine(
        runner: (_) async {
          engineCalls++;
          return const CliInstallerCommandResult(exitCode: 0);
        },
        installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
          final id = idOverride ?? d.expectedLocalId;
          final directory = d.directory.isEmpty ? 'gstack' : d.directory;
          return Skill(
            id: id,
            name: d.name,
            description: '',
            directory: directory,
            installedAt: 1,
            updatedAt: 1,
          );
        },
        listSkillDirsWithSkillMd: () async {
          if (engineCalls == 0) return {};
          return {'gstack'};
        },
        isLocalAcquireSupported: () => true,
        registerDirectory:
            ({required String id, required String directory}) async {
          return Skill(
            id: id,
            name: directory,
            description: '',
            directory: directory,
            installedAt: 1,
            updatedAt: 1,
          );
        },
      );

      final cubit = cubitWith(engine);

      final id = await cubit.installTeamDependency(
        const SkillDependencyRef(
          name: 'gstack',
          id: expectedId,
          scriptUrl: 'https://example.com/install-gstack.sh',
          repoOwner: '',
          repoName: '',
          repoBranch: 'main',
          directory: 'gstack',
        ),
      );

      expect(id, expectedId);
      expect(engineCalls, 1);
      expect(cubit.state.busyIds, isEmpty);
    },
  );

  test(
    'installTeamDependency returns expectedLocalId when already installed',
    () async {
      const expectedId = 'obra/superpowers:brainstorming';
      var engineCalls = 0;
      final engine = SkillAcquisitionEngine(
        installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
          engineCalls++;
          throw StateError('should not install');
        },
        runner: (_) async {
          engineCalls++;
          return const CliInstallerCommandResult(exitCode: 1);
        },
        isLocalAcquireSupported: () => true,
      );

      final cubit = cubitWith(engine);
      cubit.emit(
        cubit.state.copyWith(
          installed: const [
            Skill(
              id: expectedId,
              name: 'Brainstorming',
              description: '',
              directory: 'brainstorming',
              installedAt: 1,
              updatedAt: 1,
            ),
          ],
        ),
      );

      final id = await cubit.installTeamDependency(
        const SkillDependencyRef(
          repoOwner: 'obra',
          repoName: 'superpowers',
          repoBranch: 'main',
          directory: 'skills/brainstorming',
          name: 'Brainstorming',
        ),
      );

      expect(id, expectedId);
      expect(engineCalls, 0);
      expect(cubit.state.busyIds, isEmpty);
    },
  );
}
