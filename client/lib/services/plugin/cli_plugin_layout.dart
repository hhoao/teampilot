import 'dart:convert';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../cli/registry/capabilities/plugin_manifest_paths.dart';
import '../io/filesystem.dart';

/// Claude / FlashskyAI plugin directory layout (one bundle per child under `plugins/`).
class CliPluginLayout {
  CliPluginLayout._();

  static const claudeManifestDirName = '.claude-plugin';
  static const flashskyaiManifestDirName = '.flashskyai-plugin';

  /// Resolves the plugin root inside [dirPath] (handles nested checkout dirs).
  static Future<String?> resolvePluginRoot(
    Filesystem fs,
    String dirPath, {
    PluginManifestPaths paths = neutralPluginManifestPaths,
  }) async {
    final primary = await _resolveWithManifest(
      fs,
      dirPath,
      paths.manifestRelativePath,
    );
    if (primary != null) return primary;

    final fallbackPath = paths.fallbackManifestRelativePath;
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
    PluginManifestPaths paths = claudePluginManifestPaths,
  }) async {
    final ctx = fs.pathContext;
    for (final rel in _manifestCandidates(paths)) {
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

  static Iterable<String> _manifestCandidates(PluginManifestPaths paths) sync* {
    yield paths.manifestRelativePath;
    final fallback = paths.fallbackManifestRelativePath;
    if (fallback != null) yield fallback;
  }

  /// Directory name under `plugins/` — manifest `name`, else last path segment.
  static Future<String> bundleDirName(
    Filesystem fs,
    String pluginRoot, {
    PluginManifestPaths paths = claudePluginManifestPaths,
  }) async {
    final manifest = await readManifest(fs, pluginRoot, paths: paths);
    if (manifest != null) return manifest.name;
    return fs.pathContext.basename(pluginRoot);
  }

  /// Writes [target] manifest tree projected from the neutral `.plugin/` bundle.
  static Future<void> projectBundleToFlavor(
    Filesystem fs,
    String pluginRoot,
    PluginManifestPaths target,
  ) async {
    if (target.manifestDirName == neutralPluginManifestPaths.manifestDirName) {
      return;
    }
    final sourceRel = await _firstExistingManifestRel(
      fs,
      pluginRoot,
      neutralPluginManifestPaths,
    );
    final ctx = fs.pathContext;
    final sourceDir = sourceRel != null
        ? ctx.dirname(ctx.join(pluginRoot, sourceRel))
        : await _firstExistingManifestDir(
            fs,
            pluginRoot,
            neutralPluginManifestPaths,
          );
    if (sourceDir == null) return;
    final targetDir = ctx.join(pluginRoot, target.manifestDirName);
    if (sourceDir == targetDir) return;
    // Already projected (common for marketplace installs that ship every flavor).
    if ((await fs.stat(ctx.join(pluginRoot, target.manifestRelativePath)))
        .isFile) {
      return;
    }
    if ((await fs.stat(targetDir)).exists) {
      await fs.removeRecursive(targetDir);
    }
    await fs.copyTree(source: sourceDir, destination: targetDir);
  }

  /// Ensures a neutral `.plugin/plugin.json` exists in the install pool bundle.
  static Future<void> ensureNeutralPoolBundle(
    Filesystem fs,
    String installDir,
  ) async {
    final root =
        await resolvePluginRoot(
          fs,
          installDir,
          paths: neutralPluginManifestPaths,
        ) ??
        await resolvePluginRoot(
          fs,
          installDir,
          paths: claudePluginManifestPaths,
        ) ??
        installDir;
    final ctx = fs.pathContext;
    final neutralManifest = ctx.join(
      root,
      neutralPluginManifestPaths.manifestRelativePath,
    );
    if ((await fs.stat(neutralManifest)).isFile) return;

    for (final paths in [
      neutralPluginManifestPaths,
      claudePluginManifestPaths,
      cursorPluginManifestPaths,
      codexPluginManifestPaths,
      flashskyaiPluginManifestPaths,
    ]) {
      for (final rel in paths.manifestCandidates()) {
        final src = ctx.join(root, rel);
        if (!(await fs.stat(src)).isFile) continue;
        final content = await fs.readString(src);
        if (content == null || content.trim().isEmpty) continue;
        final neutralDir = ctx.join(
          root,
          neutralPluginManifestPaths.manifestDirName,
        );
        await fs.ensureDir(neutralDir);
        await fs.atomicWrite(neutralManifest, content);
        return;
      }
    }
  }

  static Future<String?> _firstExistingManifestDir(
    Filesystem fs,
    String pluginRoot,
    PluginManifestPaths paths,
  ) async {
    for (final rel in paths.manifestCandidates()) {
      final dir = fs.pathContext.dirname(fs.pathContext.join(pluginRoot, rel));
      if ((await fs.stat(dir)).isDirectory) return dir;
    }
    return null;
  }

  static Future<String?> _firstExistingManifestRel(
    Filesystem fs,
    String pluginRoot,
    PluginManifestPaths paths,
  ) async {
    for (final rel in paths.manifestCandidates()) {
      if ((await fs.stat(fs.pathContext.join(pluginRoot, rel))).isFile) {
        return rel;
      }
    }
    return null;
  }

  /// Removes a foreign flavor manifest dir from a materialized bundle.
  static Future<void> removeManifestDir(
    Filesystem fs,
    String pluginRoot,
    String manifestDirName,
  ) async {
    final dir = fs.pathContext.join(pluginRoot, manifestDirName);
    if ((await fs.stat(dir)).exists) {
      await fs.removeRecursive(dir);
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
    final linked = await fs.createSymlink(
      target: source,
      linkPath: destination,
    );
    if (linked) return true;
    await fs.copyTree(source: source, destination: destination);
    return false;
  }
}
