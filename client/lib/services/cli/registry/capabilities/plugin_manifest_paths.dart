import 'package:flutter/foundation.dart';

/// Manifest directory layout for CLI plugin bundles.
@immutable
class PluginManifestPaths {
  const PluginManifestPaths({
    required this.manifestDirName,
    this.fallbackManifestDirName,
  });

  final String manifestDirName;
  final String? fallbackManifestDirName;

  String get manifestRelativePath => '$manifestDirName/plugin.json';

  String? get fallbackManifestRelativePath {
    final fallback = fallbackManifestDirName;
    if (fallback == null) return null;
    return '$fallback/plugin.json';
  }

  Iterable<String> manifestCandidates() sync* {
    yield manifestRelativePath;
    final fallback = fallbackManifestRelativePath;
    if (fallback != null) yield fallback;
  }
}

const claudePluginManifestPaths = PluginManifestPaths(
  manifestDirName: '.claude-plugin',
);

const flashskyaiPluginManifestPaths = PluginManifestPaths(
  manifestDirName: '.flashskyai-plugin',
  fallbackManifestDirName: '.claude-plugin',
);
