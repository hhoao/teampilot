import '../cli/registry/capabilities/resource_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../../models/team_config.dart';
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
  })  : _fs = fs,
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
    final cap = _registry.capability<ResourceCapability>(cli);
    if (cap == null) return const ResourceProvisionResult();

    final effective = _resolver.resolve(scope: scope, catalog: catalog);
    final warnings = <String>[];
    for (final kind in cap.supportedKinds) {
      if (cap.representationFor(kind) != ResourceRepresentation.linkedDirectory) {
        continue; // mergedJsonEntry kinds (mcp) handled by their own plan
      }
      final kindDir = _fs.pathContext.join(configDir, cap.subdirFor(kind));
      final result = await _materializer.reconcile(
        kindDir: kindDir,
        desired: effective.of(kind),
      );
      warnings.addAll(result.errors);
    }
    return ResourceProvisionResult(warnings: warnings);
  }
}
