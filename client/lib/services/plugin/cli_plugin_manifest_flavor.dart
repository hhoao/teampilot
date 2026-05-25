

/// Which CLI reads plugin manifests under a bundle directory.
enum CliPluginManifestFlavor {
  /// Anthropic Claude Code (`.claude-plugin/plugin.json`).
  claude,

  /// FlashskyAI fork (`.flashskyai-plugin/plugin.json`, Claude-compatible layout).
  flashskyai,
}

extension CliPluginManifestFlavorPaths on CliPluginManifestFlavor {
  String get manifestDirName => switch (this) {
        CliPluginManifestFlavor.claude => '.claude-plugin',
        CliPluginManifestFlavor.flashskyai => '.flashskyai-plugin',
      };

  String get manifestRelativePath => '$manifestDirName/plugin.json';

  /// Alternate manifest dir kept for marketplace plugins (Claude-authored).
  String? get fallbackManifestDirName => switch (this) {
        CliPluginManifestFlavor.claude => null,
        CliPluginManifestFlavor.flashskyai => '.claude-plugin',
      };

  String? get fallbackManifestRelativePath {
    final fallback = fallbackManifestDirName;
    if (fallback == null) return null;
    return '$fallback/plugin.json';
  }
}

CliPluginManifestFlavor? cliPluginManifestFlavorForTool(String tool) {
  switch (tool.trim().toLowerCase()) {
    case 'claude':
      return CliPluginManifestFlavor.claude;
    case 'flashskyai':
      return CliPluginManifestFlavor.flashskyai;
    default:
      return null;
  }
}
