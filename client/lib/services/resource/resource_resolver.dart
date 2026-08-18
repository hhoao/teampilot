import '../../models/team_config.dart';
import 'assemblers/skill_assembler.dart';
import 'providers/catalog_skill_contribution_provider.dart';
import 'providers/plugin_skill_contribution_provider.dart';
import 'providers/skill_contribution_provider.dart';
import 'resource_kind.dart';
import 'resource_scope.dart';

/// Compatibility facade for the pre-contribution resource resolver API.
///
/// Resource selection, catalog filtering, source-path resolution, and stable
/// ordering live in providers and [SkillAssembler]. This class only delegates
/// to that pipeline and projects the neutral result back to [ResourceRef] for
/// callers that still consume the old result shape.
class ResourceResolver {
  const ResourceResolver();

  /// Delegates one neutral skill assembly for a launch.
  Future<SkillAssemblyResult> assemble({
    required ResourceScope scope,
    required CliTool cli,
    required ResourceCatalog catalog,
  }) {
    final providers = <SkillContributionProvider>[
      CatalogSkillContributionProvider(catalog: catalog),
      if (catalog.plugins.isNotEmpty)
        PluginSkillContributionProvider(catalog: catalog),
    ];
    return const SkillAssembler().assemble(
      context: SkillProviderContext(cli: cli, scope: scope),
      providers: providers,
    );
  }

  /// Projects the delegated neutral result into the old resource-ref shape.
  Future<EffectiveResourceSet> resolve({
    required ResourceScope scope,
    required ResourceCatalog catalog,
    CliTool cli = CliTool.claude,
  }) async {
    final assembled = await assemble(scope: scope, cli: cli, catalog: catalog);
    final refs = <ResourceRef>[];
    final usedNames = <String>{};
    for (final contribution in assembled.skills) {
      final artifact = contribution.artifact;
      if (artifact is! SkillDirectoryArtifact) continue;
      var linkName = contribution.invocationName;
      if (!usedNames.add(linkName)) {
        final namespace = contribution.namespace?.trim();
        if (namespace != null && namespace.isNotEmpty) {
          linkName = '$namespace:$linkName';
        }
        var suffix = 2;
        final base = linkName;
        while (!usedNames.add(linkName)) {
          linkName = '$base:$suffix';
          suffix++;
        }
      }
      refs.add(
        ResourceRef(
          id: contribution.id,
          linkName: linkName,
          sourceDir: artifact.sourceDirectory,
        ),
      );
    }
    return EffectiveResourceSet.immutable({ResourceKind.skill: refs});
  }
}
