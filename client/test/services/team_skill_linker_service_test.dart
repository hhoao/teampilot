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
  late String teamSkills;
  late TeamSkillLinkerService linker;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('team-skill-linker-');
    appSkills = p.join(tmp.path, 'app', 'skills');
    teamSkills = p.join(tmp.path, 'team-a', 'flashskyai', 'skills');
    linker = TeamSkillLinkerService(
      appSkillsRoot: appSkills,
      teamSkillsRootOverride: teamSkills,
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
      teamId: 'team-a',
      skillIds: ['id:alpha', 'id:beta', 'missing:id'],
      installed: [
        _skill('id:alpha', 'alpha'),
        _skill('id:beta', 'beta'),
      ],
    );

    expect(result.linked, ['alpha', 'beta']);
    expect(result.skippedMissingIds, ['missing:id']);
    expect(result.ok, isTrue);

    final alphaLink = Link(p.join(teamSkills, 'alpha'));
    expect(alphaLink.existsSync(), isTrue);
    expect(alphaLink.targetSync(), p.join(appSkills, 'alpha'));

    final betaLink = Link(p.join(teamSkills, 'beta'));
    expect(betaLink.targetSync(), p.join(appSkills, 'beta'));
  });

  test('sync replaces previous team links', () async {
    await installSource('only-a');
    await installSource('only-b');

    await linker.syncForTeam(
      teamId: 'team-a',
      skillIds: ['a'],
      installed: [_skill('a', 'only-a')],
    );
    expect(
      Directory(p.join(teamSkills, 'only-a')).existsSync() ||
          Link(p.join(teamSkills, 'only-a')).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(teamSkills, 'only-b')).existsSync() ||
          Link(p.join(teamSkills, 'only-b')).existsSync(),
      isFalse,
    );

    await linker.syncForTeam(
      teamId: 'team-a',
      skillIds: ['b'],
      installed: [_skill('b', 'only-b')],
    );
    expect(
      Link(p.join(teamSkills, 'only-b')).existsSync() ||
          Directory(p.join(teamSkills, 'only-b')).existsSync(),
      isTrue,
    );
    expect(Link(p.join(teamSkills, 'only-a')).existsSync(), isFalse);
  });

  test('sync with empty skillIds clears team dir', () async {
    await installSource('orphan');
    await linker.syncForTeam(
      teamId: 'team-a',
      skillIds: ['x'],
      installed: [_skill('x', 'orphan')],
    );
    expect(Directory(teamSkills).listSync(), isNotEmpty);

    await linker.syncForTeam(
      teamId: 'team-a',
      skillIds: const [],
      installed: const [],
    );
    expect(Directory(teamSkills).listSync(), isEmpty);
  });

  test('empty teamId is a no-op', () async {
    await installSource('alpha');

    final result = await linker.syncForTeam(
      teamId: '',
      skillIds: ['id:alpha'],
      installed: [_skill('id:alpha', 'alpha')],
    );

    expect(result.linked, isEmpty);
    expect(result.skippedMissingIds, isEmpty);
  });
}
