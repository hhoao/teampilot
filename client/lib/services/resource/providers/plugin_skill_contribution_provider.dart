import 'dart:async';

import '../../../models/plugin.dart';
import '../../../models/team_config.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import '../resource_scope.dart';
import 'skill_contribution_provider.dart';

/// Converts enabled installed plugin skill metadata into canonical directory
/// artifacts. The provider does not inspect or mutate a session directory;
/// the target capability decides how those artifacts are linked.
final class PluginSkillContributionProvider
    implements SkillContributionProvider, SkillContributionProviderDiagnostics {
  PluginSkillContributionProvider({required this.catalog, this.pluginsRoot});

  final ResourceCatalog catalog;
  final String? pluginsRoot;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'plugin';

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  FutureOr<Iterable<SkillContribution>> provide(SkillProviderContext context) {
    final scope = context.scope;
    final root = pluginsRoot ?? catalog.pluginsRoot;
    if (scope == null || root == null || root.trim().isEmpty) {
      _diagnostics = const [];
      return const [];
    }

    final byId = <String, Plugin>{};
    for (final plugin in catalog.plugins) {
      byId.putIfAbsent(plugin.id, () => plugin);
    }

    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final seenPluginIds = <String>{};
    final contributions = <SkillContribution>[];
    for (final rawId in scope.pluginIds) {
      final pluginId = rawId.trim();
      if (pluginId.isEmpty || !seenPluginIds.add(pluginId)) continue;

      final plugin = byId[pluginId];
      if (plugin == null) {
        diagnostics.add(
          _warning(
            cli: context.cli,
            sourceId: pluginId,
            message: 'Unknown plugin id $pluginId was discarded.',
          ),
        );
        continue;
      }

      for (final skill in plugin.capabilities.skills) {
        final name = skill.name.trim();
        if (name.isEmpty) continue;
        contributions.add(
          SkillContribution(
            id: '${plugin.id}:$name',
            invocationName: name,
            namespace: plugin.id,
            artifact: SkillDirectoryArtifact(
              catalog.pathContext.join(root, plugin.directory, 'skills', name),
            ),
            origin: ContributionOrigin(
              providerId: providerId,
              kind: ResourceOriginKind.plugin,
              sourceId: '${plugin.id}:$name',
            ),
          ),
        );
      }
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
