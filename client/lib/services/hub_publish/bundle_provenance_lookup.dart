import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';

/// Result of reverse-mapping local bundle ids to portable hub dependency refs.
class BundleProvenanceResult {
  const BundleProvenanceResult({
    this.skillDeps = const [],
    this.pluginDeps = const [],
    this.mcpDeps = const [],
    this.nonPortableIds = const [],
  });

  final List<SkillDependencyRef> skillDeps;
  final List<PluginDependencyRef> pluginDeps;
  final List<McpDependencyRef> mcpDeps;
  final List<String> nonPortableIds;
}

/// Reverse-looks up installed [Skill] / [Plugin] / [McpServer] provenance for
/// Hub publish. IDs without portable fields are listed in [nonPortableIds].
class BundleProvenanceLookup {
  BundleProvenanceLookup({
    required List<Skill> skills,
    required List<Plugin> plugins,
    required List<McpServer> mcps,
  }) : _skillsById = {for (final s in skills) s.id: s},
       _pluginsById = {for (final p in plugins) p.id: p},
       _mcpsById = {for (final m in mcps) m.id: m};

  final Map<String, Skill> _skillsById;
  final Map<String, Plugin> _pluginsById;
  final Map<String, McpServer> _mcpsById;

  BundleProvenanceResult resolve({
    required List<String> skillIds,
    required List<String> pluginIds,
    required List<String> mcpServerIds,
  }) {
    final skillDeps = <SkillDependencyRef>[];
    final pluginDeps = <PluginDependencyRef>[];
    final mcpDeps = <McpDependencyRef>[];
    final nonPortable = <String>[];

    for (final id in skillIds) {
      final skill = _skillsById[id];
      final dep = skill == null ? null : _skillDep(skill);
      if (dep == null) {
        nonPortable.add(id);
      } else {
        skillDeps.add(dep);
      }
    }

    for (final id in pluginIds) {
      final plugin = _pluginsById[id];
      final dep = plugin == null ? null : _pluginDep(plugin);
      if (dep == null) {
        nonPortable.add(id);
      } else {
        pluginDeps.add(dep);
      }
    }

    for (final id in mcpServerIds) {
      final mcp = _mcpsById[id];
      final dep = mcp == null ? null : _mcpDep(mcp);
      if (dep == null) {
        nonPortable.add(id);
      } else {
        mcpDeps.add(dep);
      }
    }

    return BundleProvenanceResult(
      skillDeps: skillDeps,
      pluginDeps: pluginDeps,
      mcpDeps: mcpDeps,
      nonPortableIds: nonPortable,
    );
  }

  static SkillDependencyRef? _skillDep(Skill skill) {
    final owner = skill.repoOwner?.trim() ?? '';
    final repo = skill.repoName?.trim() ?? '';
    final directory = skill.directory.trim();
    if (owner.isEmpty || repo.isEmpty || directory.isEmpty) return null;
    final branch = skill.repoBranch?.trim();
    return SkillDependencyRef(
      repoOwner: owner,
      repoName: repo,
      repoBranch: (branch == null || branch.isEmpty) ? 'main' : branch,
      directory: directory,
      name: skill.name,
    );
  }

  static PluginDependencyRef? _pluginDep(Plugin plugin) {
    final owner = plugin.marketplaceOwner?.trim() ?? '';
    final marketplace = plugin.marketplaceName?.trim() ?? '';
    if (owner.isEmpty || marketplace.isEmpty) return null;
    final entryName = _pluginEntryName(plugin);
    if (entryName.isEmpty) return null;
    final branch = plugin.marketplaceBranch?.trim();
    return PluginDependencyRef(
      marketplaceOwner: owner,
      marketplaceName: marketplace,
      marketplaceBranch: (branch == null || branch.isEmpty) ? 'main' : branch,
      entryName: entryName,
      name: plugin.name,
    );
  }

  /// Plugin has no `entryName` field — derive from `id` (`owner/marketplace/entry`)
  /// when it matches marketplace fields, else fall back to [Plugin.name].
  static String _pluginEntryName(Plugin plugin) {
    final owner = plugin.marketplaceOwner?.trim() ?? '';
    final marketplace = plugin.marketplaceName?.trim() ?? '';
    final prefix = '$owner/$marketplace/';
    if (plugin.id.startsWith(prefix)) {
      final entry = plugin.id.substring(prefix.length).trim();
      if (entry.isNotEmpty) return entry;
    }
    return plugin.name.trim();
  }

  static McpDependencyRef? _mcpDep(McpServer mcp) {
    final sanitized = sanitizeMcpServerMap(mcp.server);
    if (sanitized.isEmpty) return null;
    return McpDependencyRef(
      id: mcp.id,
      name: mcp.name,
      description: mcp.description,
      server: sanitized,
    );
  }

  /// Deep-copies [server] and strips secret-bearing keys for Hub publish.
  static Map<String, Object?> sanitizeMcpServerMap(Map<String, Object?> server) {
    return _sanitizeMap(server);
  }

  static Map<String, Object?> _sanitizeMap(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString() ?? '';
      if (key.isEmpty || _isSecretKey(key)) continue;
      final value = entry.value;
      if (value is Map) {
        final nested = _sanitizeMap(value);
        if (nested.isNotEmpty) out[key] = nested;
      } else if (value is List) {
        out[key] = _sanitizeList(value);
      } else if (value is String && _looksLikeSecretValue(key, value)) {
        continue;
      } else {
        out[key] = value;
      }
    }
    return out;
  }

  static List<Object?> _sanitizeList(List<Object?> raw) {
    return [
      for (final item in raw)
        if (item is Map)
          _sanitizeMap(item)
        else if (item is List)
          _sanitizeList(item)
        else
          item,
    ];
  }

  static bool _isSecretKey(String key) {
    final lower = key.toLowerCase();
    if (lower == 'env' ||
        lower == 'headers' ||
        lower == 'authorization' ||
        lower == 'environment') {
      return true;
    }
    if (lower.contains('token') ||
        lower.contains('apikey') ||
        lower.contains('api_key') ||
        lower.contains('secret') ||
        lower.contains('password') ||
        lower.contains('passwd') ||
        lower.contains('credential')) {
      return true;
    }
    return false;
  }

  static bool _looksLikeSecretValue(String key, String value) {
    final lowerKey = key.toLowerCase();
    if (lowerKey.contains('token') ||
        lowerKey.contains('secret') ||
        lowerKey.contains('password') ||
        lowerKey.contains('apikey') ||
        lowerKey.contains('api_key')) {
      return value.trim().isNotEmpty;
    }
    final trimmed = value.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) return true;
    return false;
  }
}
