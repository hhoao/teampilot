import 'dart:convert';

import 'cli_plugin_manifest_flavor.dart';
import 'cli_plugin_provision_cache.dart';
import 'io/filesystem.dart';

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

  static Future<bool> isPluginBundleEntry(Filesystem fs, String path) async {
    final stat = await fs.stat(path);
    return stat.isDirectory || stat.isSymlink;
  }

  /// Symlinks [source] at [destination], or copies when symlinks are unavailable.
  ///
  /// Returns `true` when a symlink was created.
  static Future<bool> linkOrCopyTree({
    required Filesystem fs,
    required String source,
    required String destination,
  }) async {
    if ((await fs.stat(destination)).exists) {
      await fs.removeRecursive(destination);
    }
    final linked = await fs.createSymlink(target: source, linkPath: destination);
    if (linked) return true;
    await fs.copyTree(source: source, destination: destination);
    return false;
  }

  /// Links (or copies) each CLI plugin bundle from [teamPluginsDir] into
  /// [memberPluginsDir].
  ///
  /// Skips provisioning when [memberPluginsDir] already matches team bundles (see
  /// [CliPluginProvisionCache]). Returns member provision stamp JSON.
  static Future<String?> copyBundlesToMember({
    required Filesystem fs,
    required String teamPluginsDir,
    required String memberPluginsDir,
    CliPluginManifestFlavor flavor = CliPluginManifestFlavor.claude,
  }) async {
    final ctx = fs.pathContext;
    final teamStat = await fs.stat(teamPluginsDir);
    if (!teamStat.isDirectory) {
      await fs.ensureDir(memberPluginsDir);
      await CliPluginProvisionCache.writeMemberProvisionStamp(
        fs: fs,
        teamPluginsDir: teamPluginsDir,
        memberPluginsDir: memberPluginsDir,
        flavor: flavor,
      );
      return await CliPluginProvisionCache.memberProvisionStampJson(
        fs: fs,
        memberPluginsDir: memberPluginsDir,
      );
    }

    if (await CliPluginProvisionCache.trySkipMemberProvision(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      memberPluginsDir: memberPluginsDir,
      flavor: flavor,
    ) case final stampJson?) {
      return stampJson;
    }

    if ((await fs.stat(memberPluginsDir)).exists) {
      await fs.removeRecursive(memberPluginsDir);
    }
    await fs.ensureDir(memberPluginsDir);

    final teamEntries = await fs.listDir(teamPluginsDir);
    final teamPluginsMtimeMs = teamStat.mtime?.millisecondsSinceEpoch ?? 0;
    final copied = await Future.wait(
      teamEntries.map((entry) async {
        final source = ctx.join(teamPluginsDir, entry.name);
        if (!await isPluginBundleEntry(fs, source)) return null;
        final root = await resolvePluginRoot(fs, source, flavor: flavor);
        if (root == null) return null;
        final dirName = await bundleDirName(fs, root, flavor: flavor);
        final dest = ctx.join(memberPluginsDir, dirName);
        final linked = await linkOrCopyTree(
          fs: fs,
          source: root,
          destination: dest,
        );
        // Symlinked member bundles share the team plugin root. FlashskyAI manifest
        // mirroring is a cheap symlink on the team root (also done at team install).
        if (linked) {
          if (flavor == CliPluginManifestFlavor.flashskyai) {
            await normalizeBundleForFlavor(fs, root, flavor);
          }
        } else {
          await normalizeBundleForFlavor(fs, dest, flavor);
        }
        final manifest = await readManifest(fs, root, flavor: flavor);
        final rootStat = await fs.stat(root);
        return {
          'dirName': dirName,
          'teamEntryName': entry.name,
          'name': manifest?.name ?? dirName,
          'version': manifest?.version ?? '0.0.0',
          'mtimeMs': rootStat.mtime?.millisecondsSinceEpoch ?? 0,
        };
      }),
    );
    final bundleStamps = copied.whereType<Map<String, Object?>>().toList();

    await CliPluginProvisionCache.writeMemberProvisionStamp(
      fs: fs,
      teamPluginsDir: teamPluginsDir,
      memberPluginsDir: memberPluginsDir,
      flavor: flavor,
      bundles: bundleStamps,
      teamPluginsMtimeMs: teamPluginsMtimeMs,
    );
    return await CliPluginProvisionCache.memberProvisionStampJson(
      fs: fs,
      memberPluginsDir: memberPluginsDir,
    );
  }
}
