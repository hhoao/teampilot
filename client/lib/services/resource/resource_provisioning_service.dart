import '../cli/registry/capabilities/plugin_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../../models/team_config.dart';
import 'contribution/resource_assembly_error.dart';
import 'resource_materializer.dart';
import 'resource_resolver.dart';
import 'resource_scope.dart';

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
       _resolver = resolver,
       _materializer = materializer ?? ResourceMaterializer(fs: fs);

  final Filesystem _fs;
  final CliToolRegistry _registry;
  final ResourceResolver _resolver;
  final ResourceMaterializer _materializer;

  Future<ResourceProvisionResult> provisionForLaunch({
    required ResourceScope scope,
    required CliTool cli,
    required String configDir,
    required ResourceCatalog catalog,
  }) async {
    final warnings = <String>[];

    final assembled = await _resolver.assemble(
      scope: scope,
      cli: cli,
      catalog: catalog,
    );
    warnings.addAll(assembled.warnings.map((diagnostic) => diagnostic.message));

    final skill = _registry.capability<SkillCapability>(cli);
    if (assembled.skills.isNotEmpty) {
      if (skill == null ||
          skill.skillsRepresentation !=
              ResourceRepresentation.linkedDirectory) {
        throw ResourceAssemblyException([
          ResourceAssemblyError.unsupported(
            resourceKind: ResourceContributionKind.skill,
            cli: cli,
            providerId: 'skill-capability',
            sourceId: cli.value,
            message: skill == null
                ? 'CLI does not provide a skill capability.'
                : 'CLI skill capability does not support linked-directory '
                      'materialization.',
          ),
        ]);
      }

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
      // Do not reconcile `plugins/` here: it contains decomposed plugin
      // bundles owned by PluginCapability. Only the assembled skill set above
      // is materialized by this facade.
    }
    return ResourceProvisionResult(warnings: warnings);
  }
}
