import '../../models/plugin.dart';

/// Result of resolving a merged plugin enable-list against the installed
/// catalog. Pure in-memory — no filesystem access.
class PluginBundleResolveResult {
  const PluginBundleResolveResult({
    this.enabled = const [],
    this.skippedMissingIds = const [],
  });

  /// Installed [Plugin]s whose id appears in the enable list, in enable-list
  /// order (deduplicated).
  final List<Plugin> enabled;

  /// Enable-list ids that do not resolve to an installed plugin.
  final List<String> skippedMissingIds;
}

/// Maps merged enable lists (`ConfigBundle.pluginIds`, already layered as
/// team > expert > workspace) to installed [Plugin]s.
///
/// This is the single id→bundle resolution used by both the launch-time pool
/// service and team-edit-time validation, so enablement feedback is consistent
/// everywhere.
abstract final class PluginBundleResolver {
  const PluginBundleResolver._();

  static PluginBundleResolveResult resolve({
    required List<String> enabledPluginIds,
    required List<Plugin> installedCatalog,
  }) {
    final byId = {for (final p in installedCatalog) p.id: p};
    final seen = <String>{};
    final enabled = <Plugin>[];
    final skipped = <String>[];
    for (final raw in enabledPluginIds) {
      final id = raw.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      final plugin = byId[id];
      if (plugin == null) {
        skipped.add(id);
      } else {
        enabled.add(plugin);
      }
    }
    return PluginBundleResolveResult(
      enabled: List.unmodifiable(enabled),
      skippedMissingIds: List.unmodifiable(skipped),
    );
  }
}
