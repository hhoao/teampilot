import 'dart:async';

import '../../../models/skill.dart';
import '../../../models/team_config.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import '../resource_scope.dart';
import 'skill_contribution_provider.dart';

/// Converts a launch scope's catalog skill ids into canonical directory
/// artifacts. It owns catalog filtering and source-path resolution so neither
/// the resolver nor a CLI capability needs to understand catalog storage.
final class CatalogSkillContributionProvider
    implements SkillContributionProvider, SkillContributionProviderDiagnostics {
  CatalogSkillContributionProvider({required this.catalog});

  final ResourceCatalog catalog;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'catalog';

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  FutureOr<Iterable<SkillContribution>> provide(SkillProviderContext context) {
    final scope = context.scope;
    if (scope == null) {
      _diagnostics = const [];
      return const [];
    }

    final byId = <String, Skill>{};
    for (final skill in catalog.skills) {
      byId.putIfAbsent(skill.id, () => skill);
    }

    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final seenIds = <String>{};
    final contributions = <SkillContribution>[];
    for (final rawId in scope.skillIds) {
      final id = rawId.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;

      final skill = byId[id];
      if (skill == null) {
        diagnostics.add(
          _warning(
            cli: context.cli,
            sourceId: id,
            message: 'Unknown catalog skill id $id was discarded.',
          ),
        );
        continue;
      }
      if (!skill.enabled) {
        diagnostics.add(
          _warning(
            cli: context.cli,
            sourceId: id,
            message: 'Disabled catalog skill id $id was discarded.',
          ),
        );
        continue;
      }

      contributions.add(
        SkillContribution(
          id: skill.id,
          invocationName: skill.directory,
          artifact: SkillDirectoryArtifact(
            catalog.pathContext.join(catalog.skillsRoot, skill.directory),
          ),
          origin: ContributionOrigin(
            providerId: providerId,
            kind: ResourceOriginKind.catalog,
            sourceId: skill.id,
          ),
        ),
      );
    }
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }

  ResourceAssemblyDiagnostic _warning({
    required CliTool cli,
    required String sourceId,
    required String message,
  }) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: ResourceContributionKind.skill,
    cli: cli,
    providerId: providerId,
    sourceId: sourceId,
    message: message,
  );
}
