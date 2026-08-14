import '../cli/registry/capabilities/plugin_capability.dart';
import '../cli/registry/capabilities/skill_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../../models/team_config.dart';
import 'resource_kind.dart';
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
    final effective = _resolver.resolve(scope: scope, catalog: catalog);
    final warnings = <String>[];

    final skill = _registry.capability<SkillCapability>(cli);
    if (skill != null &&
        skill.skillsRepresentation == ResourceRepresentation.linkedDirectory) {
      final skillDir = _fs.pathContext.join(configDir, skill.skillsSubdir);
      final result = await _materializer.reconcile(
        kindDir: skillDir,
        desired: effective.of(ResourceKind.skill),
      );
      warnings.addAll(result.errors);
    }

    final plugin = _registry.capability<PluginCapability>(cli);
    if (plugin != null &&
        plugin.pluginsRepresentation == ResourceRepresentation.linkedDirectory) {
      // ResourceResolver only ever emits skills today, so the effective plugin
      // set is always empty and this branch never reconciles. Reconcile with an
      // empty set would prune `plugins/`, which holds decomposed plugin bundles
      // — the guard below must stay (asserts are stripped in release builds).
      final desired = effective.of(ResourceKind.plugin);
      assert(
        desired.isEmpty,
        'plugin resources are not emitted by ResourceResolver yet',
      );
      if (desired.isEmpty) return ResourceProvisionResult(warnings: warnings);
      final pluginDir = _fs.pathContext.join(configDir, plugin.pluginsSubdir);
      final result = await _materializer.reconcile(
        kindDir: pluginDir,
        desired: desired,
      );
      warnings.addAll(result.errors);
    }
    return ResourceProvisionResult(warnings: warnings);
  }
}
