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
    if (scope == null) {
      _diagnostics = const [];
      return const [];
    }

    final selectedPluginIds = <String>[];
    final seenPluginIds = <String>{};
    for (final rawId in scope.pluginIds) {
      final pluginId = rawId.trim();
      if (pluginId.isNotEmpty && seenPluginIds.add(pluginId)) {
        selectedPluginIds.add(pluginId);
      }
    }
    if (root == null || root.trim().isEmpty) {
      _diagnostics = List.unmodifiable(
        selectedPluginIds.map(
          (pluginId) => _warning(
            cli: context.cli,
            sourceId: pluginId,
            message:
                'Plugin source root is unavailable for selected plugin id '
                '$pluginId.',
          ),
        ),
      );
      return const [];
    }

    final byId = <String, Plugin>{};
    for (final plugin in catalog.plugins) {
      byId.putIfAbsent(plugin.id, () => plugin);
    }

    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final contributions = <SkillContribution>[];
    for (final pluginId in selectedPluginIds) {
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

      final invalidDirectory = _invalidPathSegment(plugin.directory);
      if (invalidDirectory != null) {
        diagnostics.add(
          _warning(
            cli: context.cli,
            sourceId: plugin.id,
            message:
                'Plugin directory for ${plugin.id} is invalid '
                '($invalidDirectory).',
          ),
        );
        continue;
      }

      if (plugin.capabilities.skills.isEmpty) {
        diagnostics.add(
          _warning(
            cli: context.cli,
            sourceId: pluginId,
            message: 'Plugin metadata for $pluginId contains no skills.',
          ),
        );
      }

      for (var index = 0; index < plugin.capabilities.skills.length; index++) {
        final skill = plugin.capabilities.skills[index];
        final name = skill.name.trim();
        final invalidName = _invalidPathSegment(skill.name);
        if (invalidName != null) {
          diagnostics.add(
            _warning(
              cli: context.cli,
              sourceId: '${plugin.id}:skill[$index]',
              message:
                  'Plugin skill name for ${plugin.id} is invalid '
                  '($invalidName).',
            ),
          );
          continue;
        }
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

  String? _invalidPathSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'empty';
    if (trimmed == '.' || trimmed == '..') return 'path traversal';
    if (trimmed.contains(RegExp(r'[<>:"/\\|?*]'))) {
      return 'contains a path separator or reserved character';
    }
    if (trimmed.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      return 'contains a control character';
    }
    return null;
  }
}
