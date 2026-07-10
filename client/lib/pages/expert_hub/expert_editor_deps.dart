import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../services/hub_publish/bundle_provenance_lookup.dart';

/// Result of mapping editor selections onto portable expert dependency refs.
class ExpertEditorDepsResult {
  const ExpertEditorDepsResult({
    this.skillDeps = const [],
    this.pluginDeps = const [],
    this.mcpDeps = const [],
    this.skippedNonPortableIds = const [],
  });

  final List<SkillDependencyRef> skillDeps;
  final List<PluginDependencyRef> pluginDeps;
  final List<McpDependencyRef> mcpDeps;
  final List<String> skippedNonPortableIds;
}

/// Builds hub-portable deps from selected installed library ids.
///
/// - Portable skills/plugins → [SkillDependencyRef] / [PluginDependencyRef]
/// - MCP servers → always [McpDependencyRef] (sanitized server map)
/// - Existing deps whose local id is still selected are preserved even if the
///   library entry is missing (uninstalled) or non-portable
/// - Newly selected non-portable skills/plugins are listed in
///   [ExpertEditorDepsResult.skippedNonPortableIds] and omitted from deps
ExpertEditorDepsResult resolveExpertEditorDeps({
  required Iterable<String> selectedSkillIds,
  required Iterable<String> selectedPluginIds,
  required Iterable<String> selectedMcpIds,
  required List<Skill> skills,
  required List<Plugin> plugins,
  required List<McpServer> mcps,
  List<SkillDependencyRef> existingSkillDeps = const [],
  List<PluginDependencyRef> existingPluginDeps = const [],
  List<McpDependencyRef> existingMcpDeps = const [],
}) {
  final skillSelected = selectedSkillIds.toSet();
  final pluginSelected = selectedPluginIds.toSet();
  final mcpSelected = selectedMcpIds.toSet();

  final lookup = BundleProvenanceLookup(
    skills: skills,
    plugins: plugins,
    mcps: mcps,
  );

  final existingSkillsById = {
    for (final dep in existingSkillDeps) dep.expectedLocalId: dep,
  };
  final existingPluginsById = {
    for (final dep in existingPluginDeps) dep.expectedLocalId: dep,
  };
  final existingMcpsById = {
    for (final dep in existingMcpDeps) dep.id: dep,
  };

  final skillDeps = <SkillDependencyRef>[];
  final pluginDeps = <PluginDependencyRef>[];
  final mcpDeps = <McpDependencyRef>[];
  final skipped = <String>[];

  for (final id in skillSelected) {
    final existing = existingSkillsById[id];
    if (existing != null) {
      skillDeps.add(existing);
      continue;
    }
    final resolved = lookup.resolve(
      skillIds: [id],
      pluginIds: const [],
      mcpServerIds: const [],
    );
    if (resolved.skillDeps.isNotEmpty) {
      skillDeps.add(resolved.skillDeps.single);
    } else {
      skipped.add(id);
    }
  }

  for (final id in pluginSelected) {
    final existing = existingPluginsById[id];
    if (existing != null) {
      pluginDeps.add(existing);
      continue;
    }
    final resolved = lookup.resolve(
      skillIds: const [],
      pluginIds: [id],
      mcpServerIds: const [],
    );
    if (resolved.pluginDeps.isNotEmpty) {
      pluginDeps.add(resolved.pluginDeps.single);
    } else {
      skipped.add(id);
    }
  }

  for (final id in mcpSelected) {
    final existing = existingMcpsById[id];
    if (existing != null) {
      mcpDeps.add(existing);
      continue;
    }
    final resolved = lookup.resolve(
      skillIds: const [],
      pluginIds: const [],
      mcpServerIds: [id],
    );
    if (resolved.mcpDeps.isNotEmpty) {
      mcpDeps.add(resolved.mcpDeps.single);
    } else {
      skipped.add(id);
    }
  }

  return ExpertEditorDepsResult(
    skillDeps: skillDeps,
    pluginDeps: pluginDeps,
    mcpDeps: mcpDeps,
    skippedNonPortableIds: skipped,
  );
}

/// Local ids currently represented by [deps] (for switch initial state).
Set<String> expertEditorSelectedSkillIds(
  List<SkillDependencyRef> deps,
) => {for (final d in deps) d.expectedLocalId};

Set<String> expertEditorSelectedPluginIds(
  List<PluginDependencyRef> deps,
) => {for (final d in deps) d.expectedLocalId};

Set<String> expertEditorSelectedMcpIds(List<McpDependencyRef> deps) => {
  for (final d in deps) d.id,
};
