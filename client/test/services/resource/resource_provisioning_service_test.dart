import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_materializer.dart';
import 'package:teampilot/services/resource/resource_provisioning_service.dart';
import 'package:teampilot/services/resource/resource_scope.dart'; // ResourceScope + ResourceCatalog
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  test(
    'provisionForLaunch materializes skills into the leaf config dir',
    () async {
      final fs = AppStorage.fs;
      final tmp = await fs.createTempDir(prefix: 'prov_test_');
      final skillsRoot = fs.pathContext.join(tmp, 'skills', 'installed');
      final src = fs.pathContext.join(skillsRoot, 'demo-skill');
      await fs.ensureDir(src);
      final configDir = fs.pathContext.join(tmp, 'cfg', 'flashskyai');

      final service = ResourceProvisioningService(
        fs: fs,
        registry: CliToolRegistry.builtIn(),
      );

      await service.provisionForLaunch(
        scope: const SimpleResourceScope(
          bundle: ConfigBundle(skillIds: ['demo']),
        ),
        cli: CliTool.flashskyai,
        configDir: configDir,
        catalog: ResourceCatalog(
          skills: [
            Skill(
              id: 'demo',
              name: 'Demo',
              description: '',
              directory: 'demo-skill',
              installedAt: 0,
              updatedAt: 0,
            ),
          ],
          skillsRoot: skillsRoot,
          pathContext: fs.pathContext,
        ),
      );

      final entries = await fs.listDir(
        fs.pathContext.join(configDir, 'skills'),
      );
      expect(entries.map((e) => e.name), contains('demo-skill'));
    },
  );

  test('provisionForLaunch never reconciles the plugin dir', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'prov_plugin_test_');
    final configDir = fs.pathContext.join(tmp, 'cfg', 'flashskyai');
    final stalePlugin = fs.pathContext.join(
      configDir,
      'plugins',
      'stale-bundle',
    );
    await fs.ensureDir(stalePlugin);

    final service = ResourceProvisioningService(
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );

    await service.provisionForLaunch(
      scope: const SimpleResourceScope(bundle: ConfigBundle()),
      cli: CliTool.flashskyai,
      configDir: configDir,
      catalog: ResourceCatalog(
        skills: const [],
        skillsRoot: fs.pathContext.join(tmp, 'skills', 'installed'),
        pathContext: fs.pathContext,
      ),
    );

    final plugins = await fs.listDir(fs.pathContext.join(configDir, 'plugins'));
    expect(plugins.map((e) => e.name), contains('stale-bundle'));
  });

  test(
    'one skill reconcile keeps catalog and plugin skills and is idempotent',
    () async {
      final fs = AppStorage.fs;
      final tmp = await fs.createTempDir(prefix: 'prov_plugin_skill_test_');
      final skillsRoot = fs.pathContext.join(tmp, 'skills', 'installed');
      final catalogSource = fs.pathContext.join(skillsRoot, 'catalog-dir');
      final pluginsRoot = fs.pathContext.join(tmp, 'plugins', 'installed');
      final pluginSource = fs.pathContext.join(
        pluginsRoot,
        'plugin-dir',
        'skills',
        'plugin-skill',
      );
      await fs.ensureDir(catalogSource);
      await fs.ensureDir(pluginSource);
      final configDir = fs.pathContext.join(tmp, 'cfg', 'claude');

      final catalog = ResourceCatalog(
        skills: [
          Skill(
            id: 'catalog',
            name: 'Catalog',
            description: '',
            directory: 'catalog-dir',
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
        skillsRoot: skillsRoot,
        pathContext: fs.pathContext,
        pluginsRoot: pluginsRoot,
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
      final service = ResourceProvisioningService(
        fs: fs,
        registry: CliToolRegistry.builtIn(),
      );
      const scope = SimpleResourceScope(
        bundle: ConfigBundle(skillIds: ['catalog'], pluginIds: ['acme/plugin']),
      );

      await service.provisionForLaunch(
        scope: scope,
        cli: CliTool.claude,
        configDir: configDir,
        catalog: catalog,
      );
      final first = (await fs.listDir(
        fs.pathContext.join(configDir, 'skills'),
      )).map((entry) => entry.name).toList();

      await service.provisionForLaunch(
        scope: scope,
        cli: CliTool.claude,
        configDir: configDir,
        catalog: catalog,
      );
      final second = (await fs.listDir(
        fs.pathContext.join(configDir, 'skills'),
      )).map((entry) => entry.name).toList();

      expect(
        first,
        containsAll(<String>['catalog-dir', 'acme-plugin--plugin-skill']),
      );
      expect(second, first);
    },
  );

  test(
    'non-empty assembled skills fail when the CLI skill capability is absent',
    () async {
      final fs = AppStorage.fs;
      final tmp = await fs.createTempDir(prefix: 'prov_unsupported_test_');
      final source = fs.pathContext.join(tmp, 'skills', 'installed', 'demo');
      await fs.ensureDir(source);

      final service = ResourceProvisioningService(
        fs: fs,
        registry: _registryWithCapabilities(const []),
      );

      await expectLater(
        service.provisionForLaunch(
          scope: const SimpleResourceScope(
            bundle: ConfigBundle(skillIds: ['demo']),
          ),
          cli: CliTool.claude,
          configDir: fs.pathContext.join(tmp, 'config'),
          catalog: ResourceCatalog(
            skills: [
              Skill(
                id: 'demo',
                name: 'Demo',
                description: '',
                directory: 'demo',
                installedAt: 0,
                updatedAt: 0,
              ),
            ],
            skillsRoot: fs.pathContext.join(tmp, 'skills', 'installed'),
            pathContext: fs.pathContext,
          ),
        ),
        throwsA(
          isA<ResourceAssemblyException>().having(
            (exception) => exception.diagnostics.single,
            'diagnostic',
            isA<ResourceAssemblyError>()
                .having(
                  (diagnostic) => diagnostic.errorKind,
                  'errorKind',
                  ResourceAssemblyErrorKind.unsupported,
                )
                .having(
                  (diagnostic) => diagnostic.resourceKind,
                  'resourceKind',
                  ResourceContributionKind.skill,
                ),
          ),
        ),
      );
    },
  );

  test(
    'non-empty assembled skills fail for unsupported representation',
    () async {
      final fs = AppStorage.fs;
      final tmp = await fs.createTempDir(prefix: 'prov_representation_test_');
      final registry = _registryWithCapabilities(const [
        _UnsupportedSkillCapability(),
      ]);
      final service = ResourceProvisioningService(fs: fs, registry: registry);

      await expectLater(
        service.provisionForLaunch(
          scope: const SimpleResourceScope(
            bundle: ConfigBundle(skillIds: ['demo']),
          ),
          cli: CliTool.claude,
          configDir: fs.pathContext.join(tmp, 'config'),
          catalog: ResourceCatalog(
            skills: [
              Skill(
                id: 'demo',
                name: 'Demo',
                description: '',
                directory: 'demo',
                installedAt: 0,
                updatedAt: 0,
              ),
            ],
            skillsRoot: fs.pathContext.join(tmp, 'skills', 'installed'),
            pathContext: fs.pathContext,
          ),
        ),
        throwsA(isA<ResourceAssemblyException>()),
      );
    },
  );
}

CliToolRegistry _registryWithCapabilities(
  Iterable<CliCapability> capabilities,
) {
  final registry = CliToolRegistry();
  registry.register(_TestCliTool(capabilities));
  return registry;
}

final class _TestCliTool implements CliToolDefinition {
  const _TestCliTool(this.capabilities);

  @override
  final Iterable<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class _UnsupportedSkillCapability implements SkillCapability {
  const _UnsupportedSkillCapability();

  @override
  String get skillsSubdir => 'skills';

  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.mergedJsonEntry;

  @override
  String get skillInvocationPrefix => '/';

  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      '/$skillName';

  @override
  Future<MaterializeResult> materializeSkills({
    required Filesystem fs,
    required String configDir,
    required Iterable<SkillContribution> contributions,
    ResourceMaterializer? materializer,
  }) async => throw StateError('must not materialize unsupported skills');
}
