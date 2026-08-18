import 'resource_kind.dart';
import 'resource_scope.dart';

/// Computes the effective enabled resource set for a scope, purely in memory.
/// No filesystem access — inheritance/selection is just reading the right
/// stored enable list and filtering against the installed catalog.
class ResourceResolver {
  const ResourceResolver();

  /// Returns the stable, de-duplicated skill selection for a launch scope.
  /// Catalog enablement and source-path resolution are intentionally handled
  /// by [CatalogSkillContributionProvider].
  List<String> selectedSkillIds(ResourceScope scope) =>
      _stableIds(scope.skillIds);

  /// Returns the stable, de-duplicated plugin selection for a launch scope.
  List<String> selectedPluginIds(ResourceScope scope) =>
      _stableIds(scope.pluginIds);

  EffectiveResourceSet resolve({
    required ResourceScope scope,
    required ResourceCatalog catalog,
  }) {
    return EffectiveResourceSet.immutable({
      ResourceKind.skill: _skills(scope, catalog),
    });
  }

  List<ResourceRef> _skills(ResourceScope scope, ResourceCatalog catalog) {
    final ids = selectedSkillIds(scope);
    if (ids.isEmpty) return const [];
    // Honor the global enable toggle: a skill disabled in the library is an
    // "off switch" everywhere, even if a workspace/team still lists it in skillIds.
    final byId = {
      for (final s in catalog.skills)
        if (s.enabled) s.id: s,
    };
    final refs = <ResourceRef>[];
    for (final id in ids) {
      final skill = byId[id];
      if (skill == null) continue; // unknown / uninstalled / disabled — dropped
      refs.add(
        ResourceRef(
          id: skill.id,
          linkName: skill.directory,
          sourceDir: catalog.pathContext.join(
            catalog.skillsRoot,
            skill.directory,
          ),
        ),
      );
    }
    return refs;
  }

  List<String> _stableIds(Iterable<String> rawIds) {
    final seen = <String>{};
    return [
      for (final rawId in rawIds)
        if (rawId.trim().isNotEmpty && seen.add(rawId.trim())) rawId.trim(),
    ];
  }
}
