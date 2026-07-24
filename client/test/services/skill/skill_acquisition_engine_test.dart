import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/skill_install_recipe.dart';
import 'package:teampilot/models/skill_pack.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/skill/skill_install_service.dart';
import 'package:teampilot/services/skill/skill_manifest_service.dart';
import 'package:teampilot/services/skill/skill_pack_registry.dart';
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
  recipe: SkillInstallRecipe.scriptUrl(
    url: url,
    skillId: id ?? skillScriptIdFromPackageUrl(url),
    primaryDirectory: primaryDirectory,
    alternatives: alternatives,
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

void _plantSkillMd(String directory) {
  final skillsDir = AppPaths.skillsDirForTeampilotRoot(
    AppStorage.paths.basePath,
  );
  final dir = Directory(p.join(skillsDir, directory));
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('---\nname: x\n---\n');
}

void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  test('singleGitDir recipe calls install delegate once', () async {
    DiscoverableSkill? seen;
    final engine = SkillAcquisitionEngine(
      installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
        seen = d;
        return Skill(
          id: idOverride ?? d.expectedLocalId,
          name: d.name,
          description: '',
          directory: d.directory,
          installedAt: 1,
          updatedAt: 1,
        );
      },
    );

    final ref = SkillDependencyRef(
      name: 'Brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/brainstorming',
    );
    final result = await engine.install(ref);
    expect(result.success, isTrue);
    expect(result.skillId, 'obra/superpowers:brainstorming');
    expect(seen?.directory, 'skills/brainstorming');
  });

  test('script rejects unsafe URL before runner', () async {
    var ran = false;
    final engine = SkillAcquisitionEngine(
      runner: (_) async {
        ran = true;
        return const CliInstallerCommandResult(exitCode: 0);
      },
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final result = await engine.install(
      _scriptRef(url: 'https://evil.example.com/x;rm -rf /'),
    );
    expect(result.success, isFalse);
    expect(ran, isFalse);
  });

  test(
    'script with safe URL runs curl pipeline and registers expectedLocalId',
    () async {
      final install = SkillInstallService(manifest: SkillManifestService());
      final engine = SkillAcquisitionEngine(
        runner: (_) async {
          _plantSkillMd('gstack-office-hours');
          return const CliInstallerCommandResult(exitCode: 0);
        },
        isLocalAcquireSupported: () => true,
        installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
            throw StateError('unused'),
        registerDirectory: install.registerInstalledDirectory,
      );

      final ref = _scriptRef(
        url: 'https://example.com/install.sh',
        id: 'script:custom/gstack',
        primaryDirectory: 'gstack-office-hours',
      );
      final result = await engine.install(ref);
      expect(result.success, isTrue);
      expect(result.skillId, ref.expectedLocalId);
      final skills = await SkillManifestService().loadSkills();
      expect(skills.single.id, ref.expectedLocalId);
    },
  );

  test('unknown step fails hard', () async {
    final engine = SkillAcquisitionEngine(
      installGitDir: (_, {bool overwrite = false, String? idOverride}) async =>
          throw StateError('unused'),
    );
    final result = await engine.install(
      SkillDependencyRef(
        name: 'x',
        repoOwner: '',
        repoName: '',
        repoBranch: 'main',
        directory: '',
        recipe: const SkillInstallRecipe(
          steps: [
            SkillInstallStep(id: 'bad', uses: 'git-bundle'),
          ],
        ),
      ),
    );
    expect(result.success, isFalse);
    expect(result.message, contains('Unknown skill install step'));
  });

  test('pack recipe register-pack installs every skill id', () async {
    final installed = <String>[];
    final engine = SkillAcquisitionEngine(
      packRegistry: SkillPackRegistry(),
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
      // Avoid real network sync / FS bin link in unit test: override handlers
      // by using a pack registry with skills-only recipe.
    );

    // Use builtin pack but stub git.sync + fs.materialize via custom handlers
    // injected through a thin registry clone — instead, call register-pack via
    // a minimal pack in a custom registry.
    final mini = SkillPack(
      id: 'garrytan/gstack',
      name: 'gstack',
      repoOwner: 'garrytan',
      repoName: 'gstack',
      repoBranch: 'main',
      skills: const [
        SkillPackEntry(
          id: 'garrytan/gstack:office-hours',
          directory: 'office-hours',
          name: 'Office Hours',
        ),
        SkillPackEntry(
          id: 'garrytan/gstack:ship',
          directory: 'ship',
          name: 'Ship',
        ),
      ],
      recipe: const SkillInstallRecipe(
        steps: [
          SkillInstallStep(id: 'skills', uses: 'skill.register-pack'),
        ],
      ),
    );
    final engine2 = SkillAcquisitionEngine(
      packRegistry: SkillPackRegistry(packs: [mini]),
      installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
        final id = idOverride ?? d.expectedLocalId;
        installed.add(id);
        return _plantedSkill(id: id, directory: d.directory);
      },
    );

    final result = await engine2.install(
      const SkillDependencyRef(
        id: 'garrytan/gstack:office-hours',
        packId: 'garrytan/gstack',
        name: 'Office Hours',
        repoOwner: 'garrytan',
        repoName: 'gstack',
        repoBranch: 'main',
        directory: 'office-hours',
      ),
    );
    expect(result.success, isTrue);
    expect(installed, containsAll(['garrytan/gstack:office-hours', 'garrytan/gstack:ship']));
    expect(engine, isNotNull); // keep analyzer quiet about unused
  });
}
