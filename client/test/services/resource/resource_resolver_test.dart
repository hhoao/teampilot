import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/resource_kind.dart';
import 'package:teampilot/services/resource/resource_resolver.dart';
import 'package:teampilot/services/resource/resource_scope.dart';

Skill _skill(String id, String dir, {bool enabled = true}) => Skill(
  id: id,
  name: id,
  description: '',
  directory: dir,
  enabled: enabled,
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

  test('simple scope resolves enabled skillIds to refs', () async {
    const scope = SimpleResourceScope(bundle: ConfigBundle(skillIds: ['a']));
    final set = await resolver.resolve(scope: scope, catalog: catalog);
    final refs = set.of(ResourceKind.skill);
    expect(refs.length, 1);
    expect(refs.single.linkName, 'skill-a');
    expect(refs.single.sourceDir, '/root/skills/installed/skill-a');
  });

  test(
    'team scope resolves from team.skillIds; unknown ids are dropped',
    () async {
      final scope = TeamResourceScope(
        team: const TeamProfile(id: 't', name: 'T', skillIds: ['b', 'missing']),
      );
      final set = await resolver.resolve(scope: scope, catalog: catalog);
      expect(set.of(ResourceKind.skill).map((r) => r.linkName), ['skill-b']);
    },
  );

  test(
    'globally-disabled skills are dropped even if listed in skillIds',
    () async {
      final disabledCatalog = ResourceCatalog(
        skills: [
          _skill('a', 'skill-a', enabled: false),
          _skill('b', 'skill-b'),
        ],
        skillsRoot: '/root/skills/installed',
        pathContext: p.posix,
      );
      const scope = SimpleResourceScope(
        bundle: ConfigBundle(skillIds: ['a', 'b']),
      );
      final set = await resolver.resolve(
        scope: scope,
        catalog: disabledCatalog,
      );
      expect(set.of(ResourceKind.skill).map((r) => r.linkName), ['skill-b']);
    },
  );

  test('compatibility resolve delegates catalog and plugin assembly', () async {
    final pluginCatalog = ResourceCatalog(
      skills: [_skill('a', 'skill-a')],
      skillsRoot: '/root/skills/installed',
      pathContext: p.posix,
      pluginsRoot: '/root/plugins/installed',
      plugins: [
        Plugin(
          id: 'acme/plugin',
          name: 'Plugin',
          description: '',
          version: '1.0.0',
          directory: 'plugin-dir',
          capabilities: const PluginCapabilities(
            skills: [PluginSkillRef(name: 'plugin-skill')],
          ),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
    );
    final set = await resolver.resolve(
      scope: const SimpleResourceScope(
        bundle: ConfigBundle(skillIds: ['a'], pluginIds: ['acme/plugin']),
      ),
      catalog: pluginCatalog,
    );

    expect(set.of(ResourceKind.skill).map((ref) => ref.linkName), [
      'skill-a',
      'plugin-skill',
    ]);
  });
}
