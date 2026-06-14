import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/resource_kind.dart';
import 'package:teampilot/services/resource/resource_resolver.dart';
import 'package:teampilot/services/resource/resource_scope.dart';

Skill _skill(String id, String dir) => Skill(
      id: id,
      name: id,
      description: '',
      directory: dir,
      installedAt: 0,
      updatedAt: 0,
    );

void main() {
  final catalog = ResourceCatalog(
    skills: [_skill('a', 'skill-a'), _skill('b', 'skill-b')],
    skillsRoot: '/root/skills/installed',
    pathContext: p.posix,
  );
  const resolver = ResourceResolver();

  test('personal scope resolves enabled skillIds to refs', () {
    const scope = PersonalResourceScope(
      profile: ProjectProfile(projectId: 'p', skillIds: ['a']),
    );
    final set = resolver.resolve(scope: scope, catalog: catalog);
    final refs = set.of(ResourceKind.skill);
    expect(refs.length, 1);
    expect(refs.single.linkName, 'skill-a');
    expect(refs.single.sourceDir, '/root/skills/installed/skill-a');
  });

  test('team scope resolves from team.skillIds; unknown ids are dropped', () {
    final scope = TeamResourceScope(
      team: const TeamConfig(id: 't', name: 'T', skillIds: ['b', 'missing']),
    );
    final set = resolver.resolve(scope: scope, catalog: catalog);
    expect(set.of(ResourceKind.skill).map((r) => r.linkName), ['skill-b']);
  });
}
