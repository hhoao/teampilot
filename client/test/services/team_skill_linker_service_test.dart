import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/team_skill_linker_service.dart';

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
  late String cliSkills;
  late TeamSkillLinkerService linker;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('team-skill-linker-');
    appSkills = p.join(tmp.path, 'app', 'skills');
    cliSkills = p.join(tmp.path, 'cli', 'skills');
    linker = TeamSkillLinkerService(
      appSkillsRoot: appSkills,
      cliSkillsDir: cliSkills,
      useWslSymlinks: false,
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

  test('sync creates symlinks for team skills', () async {
    await installSource('alpha');
    await installSource('beta');

    final result = await linker.syncForTeam(
      skillIds: ['id:alpha', 'id:beta', 'missing:id'],
      installed: [
        _skill('id:alpha', 'alpha'),
        _skill('id:beta', 'beta'),
      ],
    );

    expect(result.linked, ['alpha', 'beta']);
    expect(result.skippedMissingIds, ['missing:id']);
    expect(result.ok, isTrue);

    final alphaLink = Link(p.join(cliSkills, 'alpha'));
    expect(alphaLink.existsSync(), isTrue);
    expect(alphaLink.targetSync(), p.join(appSkills, 'alpha'));

    final betaLink = Link(p.join(cliSkills, 'beta'));
    expect(betaLink.targetSync(), p.join(appSkills, 'beta'));
  });

  test('sync replaces previous team links', () async {
    await installSource('only-a');
    await installSource('only-b');

    await linker.syncForTeam(
      skillIds: ['a'],
      installed: [_skill('a', 'only-a')],
    );
    expect(Directory(p.join(cliSkills, 'only-a')).existsSync() ||
        Link(p.join(cliSkills, 'only-a')).existsSync(), isTrue);
    expect(
      Directory(p.join(cliSkills, 'only-b')).existsSync() ||
          Link(p.join(cliSkills, 'only-b')).existsSync(),
      isFalse,
    );

    await linker.syncForTeam(
      skillIds: ['b'],
      installed: [_skill('b', 'only-b')],
    );
    expect(
      Link(p.join(cliSkills, 'only-b')).existsSync() ||
          Directory(p.join(cliSkills, 'only-b')).existsSync(),
      isTrue,
    );
    expect(Link(p.join(cliSkills, 'only-a')).existsSync(), isFalse);
  });

  test('sync with empty skillIds clears cli dir', () async {
    await installSource('orphan');
    await linker.syncForTeam(
      skillIds: ['x'],
      installed: [_skill('x', 'orphan')],
    );
    expect(Directory(cliSkills).listSync(), isNotEmpty);

    await linker.syncForTeam(skillIds: const [], installed: const []);
    expect(Directory(cliSkills).listSync(), isEmpty);
  });
}
