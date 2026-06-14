import 'resource_kind.dart';
import 'resource_scope.dart';

/// Computes the effective enabled resource set for a scope, purely in memory.
/// No filesystem access — inheritance/selection is just reading the right
/// stored enable list and filtering against the installed catalog.
class ResourceResolver {
  const ResourceResolver();

  EffectiveResourceSet resolve({
    required ResourceScope scope,
    required ResourceCatalog catalog,
  }) {
    return EffectiveResourceSet({
      ResourceKind.skill: _skills(scope, catalog),
    });
  }

  List<ResourceRef> _skills(ResourceScope scope, ResourceCatalog catalog) {
    final ids = switch (scope) {
      PersonalResourceScope(:final profile) => profile.skillIds,
      TeamResourceScope(:final team) => team.skillIds,
    };
    if (ids.isEmpty) return const [];
    final byId = {for (final s in catalog.skills) s.id: s};
    final refs = <ResourceRef>[];
    for (final id in ids) {
      final skill = byId[id];
      if (skill == null) continue; // unknown / uninstalled — dropped
      refs.add(ResourceRef(
        id: skill.id,
        linkName: skill.directory,
        sourceDir: catalog.pathContext.join(catalog.skillsRoot, skill.directory),
      ));
    }
    return refs;
  }
}
