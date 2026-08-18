import '../cli/registry/capabilities/plugin_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../../models/team_config.dart';
import 'assemblers/skill_assembler.dart';
import 'resource_materializer.dart';
import 'resource_resolver.dart';
import 'resource_scope.dart';
import 'providers/catalog_skill_contribution_provider.dart';
import 'providers/plugin_skill_contribution_provider.dart';
import 'providers/skill_contribution_provider.dart';

class ResourceProvisionResult {
  const ResourceProvisionResult({this.warnings = const []});
  final List<String> warnings;
}

/// Single launch-time entry point: resolve the effective resource set for a
/// scope, then materialize every linked-directory kind the CLI supports into
/// its leaf CONFIG_DIR. Same code for personal, native, and mixed modes.
class ResourceProvisioningService {
  ResourceProvisioningService({
    required Filesystem fs,
    required CliToolRegistry registry,
    ResourceResolver resolver = const ResourceResolver(),
    ResourceMaterializer? materializer,
  }) : _fs = fs,
       _registry = registry,
       _materializer = materializer ?? ResourceMaterializer(fs: fs);

  final Filesystem _fs;
  final CliToolRegistry _registry;
  final ResourceMaterializer _materializer;

  Future<ResourceProvisionResult> provisionForLaunch({
    required ResourceScope scope,
    required CliTool cli,
    required String configDir,
    required ResourceCatalog catalog,
  }) async {
    final warnings = <String>[];

    final skill = _registry.capability<SkillCapability>(cli);
    if (skill != null &&
        skill.skillsRepresentation == ResourceRepresentation.linkedDirectory) {
      final providers = <SkillContributionProvider>[
        CatalogSkillContributionProvider(catalog: catalog),
        if (catalog.plugins.isNotEmpty)
          PluginSkillContributionProvider(catalog: catalog),
      ];
      final assembled = await const SkillAssembler().assemble(
        context: SkillProviderContext(cli: cli, scope: scope),
        providers: providers,
      );
      warnings.addAll(
        assembled.warnings.map((diagnostic) => diagnostic.message),
      );
      final result = await skill.materializeSkills(
        fs: _fs,
        configDir: configDir,
        contributions: assembled.skills,
        materializer: _materializer,
      );
      warnings.addAll(result.errors);
    }

    final plugin = _registry.capability<PluginCapability>(cli);
    if (plugin != null &&
        plugin.pluginsRepresentation ==
            ResourceRepresentation.linkedDirectory) {
      // ResourceResolver only ever emits skills today, so the effective plugin
      // set is always empty and this branch never reconciles. Reconcile with an
      // empty set would prune `plugins/`, which holds decomposed plugin bundles
      // — the guard below must stay (asserts are stripped in release builds).
      // Skills are assembled above; plugin bundles remain owned by the
      // PluginCapability pipeline until their typed provider is introduced.
    }
    return ResourceProvisionResult(warnings: warnings);
  }
}
