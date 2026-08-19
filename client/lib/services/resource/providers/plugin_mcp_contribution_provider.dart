import 'dart:async';
import 'dart:convert';

import '../../../models/mcp_server_spec.dart';
import '../../../models/plugin.dart';
import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'mcp_contribution_provider.dart';

/// Reads plugin `.mcp.json` payloads without writing target configuration.
final class PluginMcpContributionProvider
    implements McpContributionProvider, McpContributionProviderDiagnostics {
  PluginMcpContributionProvider({
    required this.fs,
    required this.pluginsRoot,
    required Iterable<Plugin> catalog,
    required Iterable<String> enabledPluginIds,
  }) : catalog = List.unmodifiable(catalog),
       enabledPluginIds = List.unmodifiable(enabledPluginIds);

  final Filesystem fs;
  final String pluginsRoot;
  final List<Plugin> catalog;
  final List<String> enabledPluginIds;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'plugin';

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  Future<Iterable<McpContribution>> provide(McpProviderContext context) async {
    final byId = <String, Plugin>{
      for (final plugin in catalog) plugin.id: plugin,
    };
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final contributions = <McpContribution>[];
    final seen = <String>{};
    for (final rawId in enabledPluginIds) {
      final pluginId = rawId.trim();
      if (pluginId.isEmpty || !seen.add(pluginId)) continue;
      final plugin = byId[pluginId];
      if (plugin == null) {
        diagnostics.add(
          _warning(
            context.cli,
            pluginId,
            'Unknown plugin id $pluginId was discarded.',
          ),
        );
        continue;
      }
      try {
        final path = fs.pathContext.join(
          pluginsRoot,
          plugin.directory,
          '.mcp.json',
        );
        final stat = await fs.stat(path);
        if (!stat.isFile) {
          if (plugin.capabilities.mcpServers.isNotEmpty) {
            diagnostics.add(
              _warning(
                context.cli,
                pluginId,
                'Plugin MCP manifest is unavailable for $pluginId.',
              ),
            );
          }
          continue;
        }
        final text = await fs.readString(path);
        if (text == null || text.trim().isEmpty) continue;
        final root = (jsonDecode(text) as Map).cast<String, Object?>();
        final servers =
            (root['mcpServers'] as Map?)?.cast<String, Object?>() ?? const {};
        for (final entry in servers.entries) {
          final spec = McpServerSpec.fromCatalogJson(
            entry.key,
            entry.value is Map
                ? (entry.value as Map).cast<String, Object?>()
                : const {},
          );
          final sourceId = '$pluginId:${entry.key}';
          if (spec == null) {
            diagnostics.add(
              _warning(
                context.cli,
                sourceId,
                'Invalid plugin MCP payload was discarded.',
              ),
            );
            continue;
          }
          contributions.add(
            McpContribution(
              sourceId: sourceId,
              server: spec,
              origin: ContributionOrigin(
                providerId: providerId,
                kind: ResourceOriginKind.plugin,
                sourceId: sourceId,
              ),
            ),
          );
        }
      } on ResourceAssemblyException {
        rethrow;
      } on Object catch (error, stackTrace) {
        throw ResourceAssemblyException([
          ResourceAssemblyError.provider(
            resourceKind: ResourceContributionKind.mcp,
            cli: context.cli,
            providerId: providerId,
            sourceId: pluginId,
            message: 'Plugin MCP provider failed: $error',
            cause: error,
            stackTrace: stackTrace,
          ),
        ]);
      }
    }
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }

  ResourceAssemblyDiagnostic _warning(
    CliTool cli,
    String sourceId,
    String message,
  ) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: ResourceContributionKind.mcp,
    cli: cli,
    providerId: providerId,
    sourceId: sourceId,
    message: message,
  );
}
