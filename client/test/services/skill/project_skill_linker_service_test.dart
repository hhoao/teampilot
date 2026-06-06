import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/skill/project_skill_linker_service.dart';

Skill _skill(String id, String directory) => Skill(
  id: id,
  name: directory,
  description: 'd',
  directory: directory,
  installedAt: 1,
  updatedAt: 1,
);

void main() {
  late Directory tmp;
  late String appSkills;
  late String projectSkills;
  late ProjectSkillLinkerService linker;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('project-skill-linker-');
    appSkills = p.join(tmp.path, 'app', 'skills');
    projectSkills = p.join(
      tmp.path,
      'config-profiles',
      'standalone',
      'projects',
      'proj-a',
      'flashskyai',
      'skills',
    );
    linker = ProjectSkillLinkerService(
      appSkillsRoot: appSkills,
      projectSkillsRootOverride: projectSkills,
    );
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> installSource(String directory) async {
    final dir = Directory(p.join(appSkills, directory));
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('# $directory');
  }

  test('sync creates symlinks under standalone project skills dir', () async {
    await installSource('alpha');
    await installSource('beta');

    final result = await linker.syncForProject(
      projectId: 'proj-a',
      skillIds: ['id:alpha', 'id:beta', 'missing:id'],
      installed: [
        _skill('id:alpha', 'alpha'),
        _skill('id:beta', 'beta'),
      ],
    );

    expect(result.linked, ['alpha', 'beta']);
    expect(result.skippedMissingIds, ['missing:id']);
    expect(result.ok, isTrue);

    final alphaLink = Link(p.join(projectSkills, 'alpha'));
    expect(alphaLink.existsSync(), isTrue);
    expect(alphaLink.targetSync(), p.join(appSkills, 'alpha'));

    final betaLink = Link(p.join(projectSkills, 'beta'));
    expect(betaLink.targetSync(), p.join(appSkills, 'beta'));
  });

  test('sync replaces previous project links', () async {
    await installSource('only-a');
    await installSource('only-b');

    await linker.syncForProject(
      projectId: 'proj-a',
      skillIds: ['a'],
      installed: [_skill('a', 'only-a')],
    );
    expect(
      Directory(p.join(projectSkills, 'only-a')).existsSync() ||
          Link(p.join(projectSkills, 'only-a')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(projectSkills, 'only-b')).existsSync() ||
          Link(p.join(projectSkills, 'only-b')).existsSync(),
      isFalse,
    );

    await linker.syncForProject(
      projectId: 'proj-a',
      skillIds: ['b'],
      installed: [_skill('b', 'only-b')],
    );
    expect(
      Link(p.join(projectSkills, 'only-b')).existsSync() ||
          Directory(p.join(projectSkills, 'only-b')).existsSync(),
      isTrue,
    );
    expect(Link(p.join(projectSkills, 'only-a')).existsSync(), isFalse);
  });

  test('sync with empty skillIds clears project dir', () async {
    await installSource('orphan');
    await linker.syncForProject(
      projectId: 'proj-a',
      skillIds: ['x'],
      installed: [_skill('x', 'orphan')],
    );
    expect(Directory(projectSkills).listSync(), isNotEmpty);

    await linker.syncForProject(
      projectId: 'proj-a',
      skillIds: const [],
      installed: const [],
    );
    expect(Directory(projectSkills).listSync(), isEmpty);
  });

  test('empty projectId is a no-op', () async {
    await installSource('alpha');

    final result = await linker.syncForProject(
      projectId: '',
      skillIds: ['id:alpha'],
      installed: [_skill('id:alpha', 'alpha')],
    );

    expect(result.linked, isEmpty);
    expect(result.skippedMissingIds, isEmpty);
  });
}
