import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/assemblers/skill_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/catalog_skill_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/plugin_skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_scope.dart';

Skill _skill(String id, String directory, {bool enabled = true}) => Skill(
  id: id,
  name: id,
  description: '',
  directory: directory,
  enabled: enabled,
  installedAt: 0,
  updatedAt: 0,
);

SkillContribution _contribution(
  String id, {
  String invocationName = 'shared',
  String? namespace,
  ResourceOriginKind originKind = ResourceOriginKind.catalog,
  String? providerId,
}) => SkillContribution(
  id: id,
  invocationName: invocationName,
  namespace: namespace,
  artifact: SkillDirectoryArtifact('/skills/$id'),
  origin: ContributionOrigin(
    providerId: providerId ?? originKind.name,
    kind: originKind,
    sourceId: id,
  ),
);

void main() {
  const cli = CliTool.claude;

  test('assembles enabled catalog skills in stable scope order', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(
        cli: cli,
        scope: SimpleResourceScope(
          bundle: ConfigBundle(skillIds: ['second', 'first']),
        ),
      ),
      providers: [
        CatalogSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: [
              _skill('first', 'first-dir'),
              _skill('second', 'second-dir'),
            ],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
          ),
        ),
      ],
    );

    expect(result.skills.map((skill) => skill.id), ['second', 'first']);
    expect(
      result.skills.map(
        (skill) => (skill.artifact! as SkillDirectoryArtifact).sourceDirectory,
      ),
      ['/catalog/skills/second-dir', '/catalog/skills/first-dir'],
    );
    expect(result.diagnostics, isEmpty);
  });

  test('drops disabled and unknown catalog ids with diagnostics', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(
        cli: cli,
        scope: const SimpleResourceScope(
          bundle: ConfigBundle(skillIds: ['disabled', 'unknown', 'enabled']),
        ),
      ),
      providers: [
        CatalogSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: [
              _skill('disabled', 'disabled-dir', enabled: false),
              _skill('enabled', 'enabled-dir'),
            ],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
          ),
        ),
      ],
    );

    expect(result.skills.map((skill) => skill.id), ['enabled']);
    expect(result.diagnostics, hasLength(2));
    expect(result.diagnostics.map((diagnostic) => diagnostic.sourceId), [
      'disabled',
      'unknown',
    ]);
    expect(
      result.diagnostics.every((diagnostic) {
        return diagnostic.resourceKind == ResourceContributionKind.skill &&
            diagnostic.cli == cli &&
            diagnostic.providerId == 'catalog';
      }),
      isTrue,
    );
  });

  test('plugin provider emits namespaced canonical skill artifacts', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(
        cli: cli,
        scope: const SimpleResourceScope(
          bundle: ConfigBundle(pluginIds: ['acme/plugin']),
        ),
      ),
      providers: [
        PluginSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: const [],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
            pluginsRoot: '/catalog/plugins/installed',
            plugins: [
              Plugin(
                id: 'acme/plugin',
                name: 'Plugin',
                description: '',
                version: '1.0.0',
                directory: 'plugin-dir',
                capabilities: const PluginCapabilities(
                  skills: [PluginSkillRef(name: 'review')],
                ),
                installedAt: 0,
                updatedAt: 0,
              ),
            ],
          ),
        ),
      ],
    );

    expect(result.diagnostics, isEmpty);
    expect(result.skills.single.id, 'acme/plugin:review');
    expect(result.skills.single.namespace, 'acme/plugin');
    expect(
      (result.skills.single.artifact! as SkillDirectoryArtifact)
          .sourceDirectory,
      '/catalog/plugins/installed/plugin-dir/skills/review',
    );
  });

  test('plugin provider diagnoses missing catalog and source root', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(
        cli: cli,
        scope: const SimpleResourceScope(
          bundle: ConfigBundle(pluginIds: ['missing/plugin']),
        ),
      ),
      providers: [
        PluginSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: const [],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
          ),
        ),
      ],
    );

    expect(result.skills, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.providerId, 'plugin');
    expect(result.diagnostics.single.sourceId, 'missing/plugin');
    expect(result.diagnostics.single.message, contains('root'));
  });

  test('catalog and plugin providers form one desired assembled set', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(
        cli: cli,
        scope: const SimpleResourceScope(
          bundle: ConfigBundle(
            skillIds: ['catalog-skill'],
            pluginIds: ['acme/plugin'],
          ),
        ),
      ),
      providers: [
        CatalogSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: [_skill('catalog-skill', 'catalog-dir')],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
            pluginsRoot: '/catalog/plugins/installed',
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
          ),
        ),
        PluginSkillContributionProvider(
          catalog: ResourceCatalog(
            skills: const [],
            skillsRoot: '/catalog/skills',
            pathContext: p.posix,
            pluginsRoot: '/catalog/plugins/installed',
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
          ),
        ),
      ],
    );

    expect(result.skills.map((skill) => skill.id), [
      'catalog-skill',
      'acme/plugin:plugin-skill',
    ]);
  });

  test('deduplicates duplicate stable ids deterministically', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(cli: cli),
      providers: [
        _Provider('first', [_contribution('same', providerId: 'first')]),
        _Provider('second', [_contribution('same', providerId: 'second')]),
      ],
    );

    expect(result.skills.single.origin.providerId, 'first');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.message, contains('same'));
  });

  test('keeps plugin namespaces isolated for equal invocation names', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(cli: cli),
      providers: [
        _Provider('plugin-one', [
          _contribution(
            'plugin-one/shared',
            namespace: 'plugin-one',
            originKind: ResourceOriginKind.plugin,
            providerId: 'plugin-one',
          ),
        ]),
        _Provider('plugin-two', [
          _contribution(
            'plugin-two/shared',
            namespace: 'plugin-two',
            originKind: ResourceOriginKind.plugin,
            providerId: 'plugin-two',
          ),
        ]),
      ],
    );

    expect(result.skills.map((skill) => skill.id), [
      'plugin-one/shared',
      'plugin-two/shared',
    ]);
    expect(result.diagnostics, isEmpty);
  });

  test('reports same-layer invocation conflicts and keeps the first', () async {
    final result = await SkillAssembler().assemble(
      context: SkillProviderContext(cli: cli),
      providers: [
        _Provider('first', [_contribution('first', providerId: 'first')]),
        _Provider('second', [_contribution('second', providerId: 'second')]),
      ],
    );

    expect(result.skills.single.id, 'first');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.message, contains('invocation'));
  });

  test(
    'preserves declared provider order when async completion differs',
    () async {
      final result = await SkillAssembler().assemble(
        context: SkillProviderContext(cli: cli),
        providers: [
          _Provider('slow', [
            _contribution('slow', invocationName: 'slow'),
          ], delay: const Duration(milliseconds: 20)),
          _Provider('fast', [
            _contribution('fast', invocationName: 'fast'),
          ], delay: const Duration(milliseconds: 1)),
        ],
      );

      expect(result.skills.map((skill) => skill.id), ['slow', 'fast']);
    },
  );

  test('provider errors carry metadata and preserve the provider id', () async {
    final future = SkillAssembler().assemble(
      context: SkillProviderContext(cli: cli, sourceId: 'skill-source'),
      providers: [_Provider('broken', const [], error: StateError('boom'))],
    );

    await expectLater(
      future,
      throwsA(
        isA<ResourceAssemblyException>().having(
          (exception) => exception.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having(
                (diagnostic) => diagnostic.providerId,
                'providerId',
                'broken',
              )
              .having(
                (diagnostic) => diagnostic.sourceId,
                'sourceId',
                'skill-source',
              )
              .having((diagnostic) => diagnostic.cli, 'cli', cli)
              .having(
                (diagnostic) => diagnostic.resourceKind,
                'resourceKind',
                ResourceContributionKind.skill,
              ),
        ),
      ),
    );
  });
}

final class _Provider implements SkillContributionProvider {
  _Provider(this.providerId, this.contributions, {this.delay, this.error});

  @override
  final String providerId;
  final List<SkillContribution> contributions;
  final Duration? delay;
  final Object? error;

  @override
  Future<Iterable<SkillContribution>> provide(
    SkillProviderContext context,
  ) async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return contributions;
  }
}
