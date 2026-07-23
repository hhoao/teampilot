import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_acquire_spec.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_install_service.dart';
import 'package:teampilot/services/skill/skill_manifest_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

SkillDependencyRef _scriptRef({
  required String url,
  String name = 'gstack',
  String? id,
  List<String> alternatives = const [],
  String? primaryDirectory,
}) => SkillDependencyRef(
  name: name,
  id: id,
  acquire: SkillAcquireSpec(
    kind: 'script',
    package: url,
    alternatives: alternatives,
    primaryDirectory: primaryDirectory,
  ),
  repoOwner: '',
  repoName: '',
  repoBranch: 'main',
  directory: '',
);

Skill _plantedSkill({required String id, required String directory}) => Skill(
  id: id,
  name: directory,
  description: '',
  directory: directory,
  installedAt: 1,
  updatedAt: 1,
);

void _plantSkillMd(String directory, {String? name}) {
  final skillsDir = AppPaths.skillsDirForTeampilotRoot(AppStorage.paths.basePath);
  final dir = Directory(p.join(skillsDir, directory));
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'SKILL.md')).writeAsStringSync(
    '---\nname: ${name ?? directory}\ndescription: planted\n---\nbody\n',
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('git-dir calls install delegate once and returns skill id', () async {
    var calls = 0;
    DiscoverableSkill? seen;
    final engine = SkillAcquisitionEngine(
      installGitDir: (d, {bool overwrite = false}) async {
        calls++;
        seen = d;
        return _plantedSkill(id: 'obra/superpowers:brainstorming', directory: 'brainstorming');
      },
      runner: (_) async => const CliInstallerCommandResult(exitCode: 0),
    );

    final result = await engine.install(
      const SkillDependencyRef(
        repoOwner: 'obra',
        repoName: 'superpowers',
        repoBranch: 'main',
        directory: 'skills/brainstorming',
        name: 'Brainstorming',
      ),
    );

    expect(calls, 1);
    expect(seen?.directory, 'skills/brainstorming');
    expect(result.success, isTrue);
    expect(result.skillId, 'obra/superpowers:brainstorming');
  });

  test('script rejects unsafe URL before runner', () async {
    var ran = false;
    final engine = SkillAcquisitionEngine(
      runner: (_) async {
        ran = true;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      isLocalAcquireSupported: () => true,
      installGitDir: (_, {bool overwrite = false}) async =>
          throw StateError('unused'),
    );

    final result = await engine.install(
      _scriptRef(url: 'https://evil.example.com/a.sh; rm -rf /'),
    );

    expect(ran, isFalse);
    expect(result.success, isFalse);
  });

  test(
    'script with safe URL runs curl pipeline and registers expectedLocalId',
    () async {
      final commands = <CliInstallerCommand>[];
      late SkillManifestService manifest;
      late SkillInstallService install;
      manifest = SkillManifestService();
      install = SkillInstallService(manifest: manifest);

      final engine = SkillAcquisitionEngine(
        runner: (cmd) async {
          commands.add(cmd);
          _plantSkillMd('install-gstack');
          return const CliInstallerCommandResult(exitCode: 0);
        },
        isLocalAcquireSupported: () => true,
        installGitDir: (_, {bool overwrite = false}) async =>
            throw StateError('unused'),
        registerDirectory: install.registerInstalledDirectory,
      );

      final ref = _scriptRef(
        url: 'https://cdn.example.com/path/install-gstack.sh',
      );
      final result = await engine.install(ref);

      expect(commands, hasLength(1));
      expect(commands.single.executable, 'sh');
      expect(
        commands.single.arguments,
        ['-c', 'curl -fsSL "https://cdn.example.com/path/install-gstack.sh" | sh'],
      );
      expect(result.success, isTrue);
      expect(result.skillId, ref.expectedLocalId);
      expect(result.skillId, 'script:cdn.example.com/install-gstack.sh');

      final skills = await manifest.loadSkills();
      expect(skills.single.id, ref.expectedLocalId);
      expect(skills.single.directory, 'install-gstack');
    },
  );

  test('unknown kind fails without calling runner', () async {
    var ran = false;
    final engine = SkillAcquisitionEngine(
      runner: (_) async {
        ran = true;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      isLocalAcquireSupported: () => true,
      installGitDir: (_, {bool overwrite = false}) async =>
          throw StateError('unused'),
    );

    final result = await engine.install(
      const SkillDependencyRef(
        name: 'x',
        acquire: SkillAcquireSpec(kind: 'git-bundle', package: 'ignored'),
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
      ),
    );

    expect(ran, isFalse);
    expect(result.success, isFalse);
  });

  test('script exit 0 but no new SKILL.md is failure', () async {
    final engine = SkillAcquisitionEngine(
      runner: (_) async => const CliInstallerCommandResult(exitCode: 0),
      isLocalAcquireSupported: () => true,
      installGitDir: (_, {bool overwrite = false}) async =>
          throw StateError('unused'),
      registerDirectory: ({required String id, required String directory}) async {
        throw StateError('should not register');
      },
    );

    final result = await engine.install(
      _scriptRef(url: 'https://example.com/install.sh'),
    );

    expect(result.success, isFalse);
    expect(result.skillId, isNull);
  });

  test('alternatives: primary fails then alternative script succeeds', () async {
    final commands = <CliInstallerCommand>[];
    final install = SkillInstallService(manifest: SkillManifestService());

    final engine = SkillAcquisitionEngine(
      runner: (cmd) async {
        commands.add(cmd);
        final script = cmd.arguments.last;
        if (script.contains('primary.sh')) {
          return const CliInstallerCommandResult(exitCode: 1, stderr: 'primary failed');
        }
        _plantSkillMd('alt-skill');
        return const CliInstallerCommandResult(exitCode: 0);
      },
      isLocalAcquireSupported: () => true,
      installGitDir: (_, {bool overwrite = false}) async =>
          throw StateError('unused'),
      registerDirectory: install.registerInstalledDirectory,
    );

    final ref = _scriptRef(
      url: 'https://example.com/primary.sh',
      alternatives: ['script:https://example.com/alt.sh'],
      id: 'script:custom/gstack',
      primaryDirectory: 'alt-skill',
    );
    final result = await engine.install(ref);

    expect(commands.map((c) => c.executable), ['sh', 'sh']);
    expect(commands.first.arguments.last, contains('primary.sh'));
    expect(commands.last.arguments.last, contains('alt.sh'));
    expect(result.success, isTrue);
    expect(result.skillId, 'script:custom/gstack');
  });

  test('unsupported host never calls runner for script', () async {
    var ran = false;
    final engine = SkillAcquisitionEngine(
      runner: (_) async {
        ran = true;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      isLocalAcquireSupported: () => false,
      installGitDir: (_, {bool overwrite = false}) async =>
          throw StateError('unused'),
    );

    final result = await engine.install(
      _scriptRef(url: 'https://example.com/install.sh'),
    );

    expect(ran, isFalse);
    expect(result.success, isFalse);
    expect(result.message.toLowerCase(), contains('not supported'));
  });
}
