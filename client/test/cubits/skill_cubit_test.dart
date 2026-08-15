import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/discovery_settings_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_fetch_service.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
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

      final cubit = SkillCubit(
        SkillRepository(),
        acquisitionEngine: engine,
      );

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

  test('manual mode syncs repos without disk cache once', () async {
    final fetch = _FakeSkillFetch();
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch),
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('manual mode with disk cache does not hit network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    expect(fetch.downloads, 1);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.downloads, 1);
    expect(fetch.shaChecks, 0);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with fresh cache skips network', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.load();
    await settings.setAutoRefreshEnabled(true);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 0);
    expect(fetch.downloads, 1);
    expect(cubit.state.discoverable, isNotEmpty);
  });

  test('auto mode with stale cache checks remote', () async {
    final fetch = _FakeSkillFetch();
    final cache = SkillRepoDiskCacheService(fetch: fetch);
    await cache.ensureSynced(_discoveryRepo);
    final fs = AppStorage.fs;
    final metaPath = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(_discoveryRepo),
      'meta.json',
    );
    final stale = SkillRepoCacheMeta(
      configuredBranch: 'main',
      resolvedBranch: 'main',
      commitSha: 'abc123',
      syncedAtMs: 1,
    );
    await fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(stale.toJson()),
    );
    final settings = DiscoverySettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    await settings.setAutoRefreshEnabled(true);
    final cubit = SkillCubit(
      SkillRepository(fetch: fetch, repoCache: cache),
      discoverySettings: settings,
    );
    _emitRepos(cubit);

    await cubit.ensureDiscoveryLoaded();

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 1);
  });
}

const _discoveryRepo = SkillRepo(owner: 'acme', name: 'skills', branch: 'main');

class _FakeSkillFetch extends SkillFetchService {
  int downloads = 0;
  int shaChecks = 0;

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    shaChecks++;
    return null;
  }

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  downloadRepoEntries(
    SkillRepo repo, {
    Filesystem? fs,
    String? persistentGitPath,
  }) async {
    downloads++;
    return (
      entries: {
        'demo/SKILL.md': Uint8List.fromList(
          utf8.encode('---\nname: demo\ndescription: d\n---\n'),
        ),
      },
      branch: repo.branch,
      commitSha: 'abc123',
    );
  }
}

void _emitRepos(SkillCubit cubit) {
  cubit.emit(cubit.state.copyWith(repos: const [_discoveryRepo]));
}
