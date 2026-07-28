import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void _plantSkillMdUnder(String syncRoot, String dirName) {
  final dir = Directory(p.join(syncRoot, dirName));
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
    '---\nname: $dirName\n---\n',
  );
}

String _syncRootFor(SkillRepo repo) => p.join(
  AppStorage.paths.skillRepoCacheDir,
  SkillRepoDiskCacheService.repoKey(repo),
  'files',
);

Future<SkillRepoSyncResult> _fakeSync(SkillRepo repo) async {
  await Directory(_syncRootFor(repo)).create(recursive: true);
  return SkillRepoSyncResult(
    skills: const [],
    updated: true,
    repoKey: SkillRepoDiskCacheService.repoKey(repo),
  );
}

SkillAcquisitionEngine _engine({
  required List<String> installed,
  SkillPackRegistry? packRegistry,
  SkillInstallRunner? runner,
}) {
  return SkillAcquisitionEngine(
    packRegistry: packRegistry,
    runner: runner,
    ensureSynced: _fakeSync,
    installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
      final id = idOverride ?? d.expectedLocalId;
      installed.add(id);
      return Skill(
        id: id,
        name: d.name,
        description: '',
        directory: d.directory,
        installedAt: 1,
        updatedAt: 1,
      );
    },
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('FROM + SKILLS review registers packId:review', () async {
    final installed = <String>[];
    final pack = SkillPack(
      id: 'owner/pack',
      name: 'pack',
      install: [
        FromInstruction.parseRef('owner/repo@main'),
        const SkillsInstruction(includeAll: false, include: ['review']),
      ],
    );
    final engine = _engine(
      installed: installed,
      packRegistry: SkillPackRegistry(packs: [pack]),
    );
    _plantSkillMdUnder(
      _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo')),
      'review',
    );

    final result = await engine.install(
      const SkillDependencyRef(
        id: 'owner/pack:review',
        name: 'Review',
        packId: 'owner/pack',
        directory: 'review',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
      ),
    );
    expect(result.success, isTrue);
    expect(installed, ['owner/pack:review']);
  });

  test('FROM + SKILLS * discovers dirs with SKILL.md', () async {
    final installed = <String>[];
    final pack = SkillPack(
      id: 'owner/pack',
      name: 'pack',
      install: [
        FromInstruction.parseRef('owner/repo@main'),
        const SkillsInstruction(includeAll: true),
      ],
    );
    final engine = _engine(
      installed: installed,
      packRegistry: SkillPackRegistry(packs: [pack]),
    );
    final root = _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo'));
    _plantSkillMdUnder(root, 'review');
    _plantSkillMdUnder(root, 'ship');
    Directory(p.join(root, 'docs')).createSync(recursive: true);

    final result = await engine.install(
      const SkillDependencyRef(
        id: 'owner/pack:review',
        name: 'Review',
        packId: 'owner/pack',
        directory: 'review',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
      ),
    );
    expect(result.success, isTrue);
    expect(installed.toSet(), {'owner/pack:review', 'owner/pack:ship'});
  });

  test('SKILLS include/exclude', () async {
    final installed = <String>[];
    final pack = SkillPack(
      id: 'owner/pack',
      name: 'pack',
      install: [
        FromInstruction.parseRef('owner/repo@main'),
        const SkillsInstruction(includeAll: true, exclude: ['qa']),
      ],
    );
    final engine = _engine(
      installed: installed,
      packRegistry: SkillPackRegistry(packs: [pack]),
    );
    final root = _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo'));
    _plantSkillMdUnder(root, 'review');
    _plantSkillMdUnder(root, 'qa');

    final result = await engine.install(
      const SkillDependencyRef(
        id: 'owner/pack:review',
        name: 'Review',
        packId: 'owner/pack',
        directory: 'review',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
      ),
    );
    expect(result.success, isTrue);
    expect(installed, ['owner/pack:review']);
  });

  test('single-dep expected id registers as my-id', () async {
    final installed = <String>[];
    final engine = _engine(installed: installed);
    final root = _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo'));
    _plantSkillMdUnder(root, 'dir');

    final result = await engine.install(
      const SkillDependencyRef(
        id: 'my-id',
        name: 'Dir',
        directory: 'dir',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
      ),
    );
    expect(result.success, isTrue);
    expect(installed, ['my-id']);
  });

  test('non-pack multi-dir SKILLS uses basename not expectedSkillId', () async {
    final installed = <String>[];
    final engine = _engine(installed: installed);
    final root = _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo'));
    _plantSkillMdUnder(root, 'alpha');
    _plantSkillMdUnder(root, 'beta');

    final result = await engine.install(
      SkillDependencyRef(
        id: 'my-id',
        name: 'Multi',
        directory: '',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const SkillsInstruction(includeAll: true),
        ],
      ),
    );
    expect(result.success, isTrue);
    expect(installed.toSet(), {'alpha', 'beta'});
    expect(installed, isNot(contains('my-id')));
  });

  test('packId dep fails when SKILLS does not register expected id', () async {
    final installed = <String>[];
    final pack = SkillPack(
      id: 'owner/pack',
      name: 'pack',
      install: [
        FromInstruction.parseRef('owner/repo@main'),
        const SkillsInstruction(includeAll: false, include: ['ship']),
        const PathInstruction(['bin']),
      ],
    );
    final engine = _engine(
      installed: installed,
      packRegistry: SkillPackRegistry(packs: [pack]),
    );
    final root = _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo'));
    _plantSkillMdUnder(root, 'ship');
    await Directory(p.join(root, 'bin')).create(recursive: true);

    final result = await engine.install(
      const SkillDependencyRef(
        id: 'owner/pack:review',
        name: 'Review',
        packId: 'owner/pack',
        directory: 'review',
        repoOwner: 'owner',
        repoName: 'repo',
        repoBranch: 'main',
      ),
    );
    expect(result.success, isFalse);
    expect(result.message, contains('owner/pack:review'));
    expect(installed, ['owner/pack:ship']);
  });

  test('optional RUN failure still applies PATH', () async {
    CliInstallerCommand? seen;
    final engine = SkillAcquisitionEngine(
      runner: (cmd) async {
        seen = cmd;
        return const CliInstallerCommandResult(exitCode: 1, stderr: 'boom');
      },
      ensureSynced: (repo) async {
        final root = _syncRootFor(repo);
        await Directory(root).create(recursive: true);
        await Directory(p.join(root, 'bin')).create(recursive: true);
        return SkillRepoSyncResult(
          skills: const [],
          updated: true,
          repoKey: SkillRepoDiskCacheService.repoKey(repo),
        );
      },
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const RunInstruction(shell: './setup', optional: true),
          const PathInstruction(['bin']),
        ],
      ),
    );
    expect(out.success, isTrue);
    expect(out.pathExports.single, endsWith('${p.separator}bin'));
    expect(seen?.executable, isNot(equals('')));
  });

  test('SHELL wraps string RUN', () async {
    CliInstallerCommand? seen;
    final engine = SkillAcquisitionEngine(
      runner: (cmd) async {
        seen = cmd;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      ensureSynced: _fakeSync,
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const ShellInstruction(['bash', '-lc']),
          const RunInstruction(shell: './setup'),
        ],
      ),
    );
    expect(out.success, isTrue);
    expect(seen?.executable, 'bash');
    expect(seen?.arguments, ['-lc', './setup']);
  });

  test('exec RUN ignores SHELL', () async {
    CliInstallerCommand? seen;
    final engine = SkillAcquisitionEngine(
      runner: (cmd) async {
        seen = cmd;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      ensureSynced: _fakeSync,
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const ShellInstruction(['bash', '-lc']),
          const RunInstruction(exec: ['./setup']),
        ],
      ),
    );
    expect(out.success, isTrue);
    expect(seen?.executable, './setup');
    expect(seen?.arguments, isEmpty);
  });

  test('PATH bin resolves under sync root', () async {
    final engine = SkillAcquisitionEngine(
      ensureSynced: (repo) async {
        final root = _syncRootFor(repo);
        await Directory(root).create(recursive: true);
        await Directory(p.join(root, 'bin')).create(recursive: true);
        return SkillRepoSyncResult(
          skills: const [],
          updated: true,
          repoKey: SkillRepoDiskCacheService.repoKey(repo),
        );
      },
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const PathInstruction(['bin']),
        ],
      ),
    );
    expect(out.success, isTrue);
    expect(out.pathExports.single, endsWith('${p.separator}bin'));
  });

  test('COPY then file exists at workdir destination', () async {
    final engine = SkillAcquisitionEngine(
      ensureSynced: (repo) async {
        final root = _syncRootFor(repo);
        await Directory(root).create(recursive: true);
        await File(p.join(root, 'src.txt')).writeAsString('hi');
        await Directory(p.join(root, 'out')).create(recursive: true);
        return SkillRepoSyncResult(
          skills: const [],
          updated: true,
          repoKey: SkillRepoDiskCacheService.repoKey(repo),
        );
      },
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          FromInstruction.parseRef('owner/repo@main'),
          const WorkdirInstruction('out'),
          const CopyInstruction(from: 'src.txt', to: 'copied.txt'),
        ],
      ),
    );
    expect(out.success, isTrue);
    final dest = p.join(
      _syncRootFor(const SkillRepo(owner: 'owner', name: 'repo')),
      'out',
      'copied.txt',
    );
    expect(File(dest).existsSync(), isTrue);
    expect(File(dest).readAsStringSync(), 'hi');
  });

  test('rejects workspace op before FROM', () async {
    final engine = SkillAcquisitionEngine(
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final out = await engine.install(
      const SkillDependencyRef(
        name: 'x',
        id: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        install: [
          PathInstruction(['bin']),
        ],
      ),
    );
    expect(out.success, isFalse);
    expect(out.message, contains('PATH'));
    expect(out.message, contains('FROM'));
  });
}
