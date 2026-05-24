import 'dart:convert';

import 'io/filesystem.dart';
import 'cli_plugin_manifest_flavor.dart';

/// Claude / FlashskyAI plugin directory layout (one bundle per child under `plugins/`).
class CliPluginLayout {
  CliPluginLayout._();

  static const claudeManifestDirName = '.claude-plugin';
  static const flashskyaiManifestDirName = '.flashskyai-plugin';

  /// Resolves the plugin root inside [dirPath] (handles nested checkout dirs).
  static Future<String?> resolvePluginRoot(
    Filesystem fs,
    String dirPath, {
    CliPluginManifestFlavor flavor = CliPluginManifestFlavor.claude,
  }) async {
    final primary = await _resolveWithManifest(fs, dirPath, flavor.manifestRelativePath);
    if (primary != null) return primary;

    final fallbackPath = flavor.fallbackManifestRelativePath;
    if (fallbackPath != null) {
      return _resolveWithManifest(fs, dirPath, fallbackPath);
    }
    return null;
  }

  static Future<String?> _resolveWithManifest(
    Filesystem fs,
    String dirPath,
    String manifestRelativePath,
  ) async {
    final ctx = fs.pathContext;
    final manifest = ctx.join(dirPath, manifestRelativePath);
    if ((await fs.stat(manifest)).isFile) return dirPath;

    for (final entry in await fs.listDir(dirPath)) {
      if (!entry.isDirectory) continue;
      final child = ctx.join(dirPath, entry.name);
      final childManifest = ctx.join(child, manifestRelativePath);
      if ((await fs.stat(childManifest)).isFile) return child;
    }
    return null;
  }

  /// Reads manifest JSON using [flavor] paths (with Claude fallback on FlashskyAI).
  static Future<({String name, String version})?> readManifest(
    Filesystem fs,
    String pluginRoot, {
    CliPluginManifestFlavor flavor = CliPluginManifestFlavor.claude,
  }) async {
    final ctx = fs.pathContext;
    for (final rel in _manifestCandidates(flavor)) {
      final text = await fs.readString(ctx.join(pluginRoot, rel));
      if (text == null || text.trim().isEmpty) continue;
      try {
        final json = (jsonDecode(text) as Map).cast<String, Object?>();
        final name = (json['name'] as String?)?.trim();
        final version = (json['version'] as String?)?.trim() ?? '0.0.0';
        if (name != null && name.isNotEmpty) {
          return (name: name, version: version);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Iterable<String> _manifestCandidates(CliPluginManifestFlavor flavor) sync* {
    yield flavor.manifestRelativePath;
    final fallback = flavor.fallbackManifestRelativePath;
    if (fallback != null) yield fallback;
  }

  /// Directory name under `plugins/` — manifest `name`, else last path segment.
  static Future<String> bundleDirName(
    Filesystem fs,
    String pluginRoot, {
    CliPluginManifestFlavor flavor = CliPluginManifestFlavor.claude,
  }) async {
    final manifest = await readManifest(fs, pluginRoot, flavor: flavor);
    if (manifest != null) return manifest.name;
    return fs.pathContext.basename(pluginRoot);
  }

  /// Ensures FlashskyAI manifest exists (mirror `.claude-plugin` when needed).
  static Future<void> normalizeBundleForFlavor(
    Filesystem fs,
    String pluginRoot,
    CliPluginManifestFlavor flavor,
  ) async {
    if (flavor != CliPluginManifestFlavor.flashskyai) return;
    await _ensureFlashskyaiPluginManifest(fs, pluginRoot);
  }

  static Future<void> _ensureFlashskyaiPluginManifest(
    Filesystem fs,
    String pluginRoot,
  ) async {
    final ctx = fs.pathContext;
    final flashskyaiManifest = ctx.join(
      pluginRoot,
      CliPluginManifestFlavor.flashskyai.manifestRelativePath,
    );
    if ((await fs.stat(flashskyaiManifest)).isFile) return;

    final claudeDir = ctx.join(pluginRoot, claudeManifestDirName);
    final hasClaudeManifest =
        (await fs.stat(ctx.join(claudeDir, 'plugin.json'))).isFile ||
        (await fs.stat(ctx.join(claudeDir, 'marketplace.json'))).isFile;
    if (!hasClaudeManifest) return;

    final flashskyaiDir = ctx.join(pluginRoot, flashskyaiManifestDirName);
    if ((await fs.stat(flashskyaiDir)).exists) {
      await fs.removeRecursive(flashskyaiDir);
    }

    final linked = await fs.createSymlink(
      target: claudeDir,
      linkPath: flashskyaiDir,
    );
    if (!linked) {
      await fs.copyTree(source: claudeDir, destination: flashskyaiDir);
    }
  }

  /// Copies each CLI plugin bundle from [teamPluginsDir] into [memberPluginsDir].
  static Future<void> copyBundlesToMember({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    CliPluginManifestFlavor flavor = CliPluginManifestFlavor.claude,
  }) async {
    final ctx = fs.pathContext;
    final teamStat = await fs.stat(teamPluginsDir);
    if (!teamStat.isDirectory) {
      await fs.ensureDir(memberPluginsDir);
      return;
    }

    if ((await fs.stat(memberPluginsDir)).exists) {
      await fs.removeRecursive(memberPluginsDir);
    }
    await fs.ensureDir(memberPluginsDir);

    for (final entry in await fs.listDir(teamPluginsDir)) {
      if (!entry.isDirectory) continue;
      final source = ctx.join(teamPluginsDir, entry.name);
      final root = await resolvePluginRoot(fs, source, flavor: flavor);
      if (root == null) continue;
      final dirName = await bundleDirName(fs, root, flavor: flavor);
      final dest = ctx.join(memberPluginsDir, dirName);
      if ((await fs.stat(dest)).exists) {
        await fs.removeRecursive(dest);
      }
      await fs.copyTree(source: root, destination: dest);
      await normalizeBundleForFlavor(fs, dest, flavor);
    }
  }
}
