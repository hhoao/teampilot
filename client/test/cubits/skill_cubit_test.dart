import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_acquire_spec.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
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
    tmp.deleteSync(recursive: true);
  });

  test(
    'loadAll() populates installed + repos without discovery sync',
    () async {
      final cubit = SkillCubit(SkillRepository());
      await cubit.loadAll();
      expect(cubit.state.status, SkillLoadStatus.ready);
      expect(cubit.state.repos, isNotEmpty);
      expect(cubit.state.installed, isEmpty);
      expect(cubit.state.discoverable, isEmpty);
      expect(cubit.state.discoveryLoading, isFalse);
      expect(cubit.state.repoSyncingKeys, isEmpty);
    },
  );

  test(
    'ensureDiscoveryLoaded does not re-sync when list is populated',
    () async {
      final cubit = SkillCubit(SkillRepository());
      cubit.emit(
        cubit.state.copyWith(
          discoverable: const [
            DiscoverableSkill(
              key: 'a:b:c',
              name: 'c',
              description: '',
              directory: 'c',
              repoOwner: 'o',
              repoName: 'n',
              repoBranch: 'main',
            ),
          ],
        ),
      );
      await cubit.ensureDiscoveryLoaded();
      expect(cubit.state.discoveryLoading, isFalse);
      expect(cubit.state.repoSyncingKeys, isEmpty);
    },
  );

  test(
    'installTeamDependency script acquire returns expectedLocalId via engine',
    () async {
      const expectedId = 'script:example.com/install-gstack.sh';
      var engineCalls = 0;
      final engine = SkillAcquisitionEngine(
        installGitDir: (d, {bool overwrite = false, String? idOverride}) async =>
            throw StateError('git-dir should not run'),
        runner: (_) async {
          engineCalls++;
          return const CliInstallerCommandResult(exitCode: 0);
        },
        registerDirectory: ({required String id, required String directory}) async =>
            Skill(
              id: id,
              name: 'gstack',
              description: '',
              directory: directory,
              installedAt: 1,
              updatedAt: 1,
            ),
        listSkillDirsWithSkillMd: () async {
          if (engineCalls == 0) return {};
          return {'gstack'};
        },
        isLocalAcquireSupported: () => true,
      );

      final cubit = SkillCubit(
        SkillRepository(),
        acquisitionEngine: engine,
      );

      final id = await cubit.installTeamDependency(
        SkillDependencyRef(
          name: 'gstack',
          acquire: const SkillAcquireSpec(
            kind: 'script',
            package: 'https://example.com/install-gstack.sh',
            primaryDirectory: 'gstack',
          ),
          repoOwner: '',
          repoName: '',
          repoBranch: 'main',
          directory: '',
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

      final cubit = SkillCubit(
        SkillRepository(),
        acquisitionEngine: engine,
      );
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
