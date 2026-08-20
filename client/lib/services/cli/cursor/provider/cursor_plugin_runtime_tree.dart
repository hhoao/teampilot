import '../../../io/filesystem.dart';
import '../../../plugin/cli_plugin_layout.dart';
import '../../registry/capabilities/plugin_capability.dart';
import '../../registry/capabilities/plugin_manifest_paths.dart';

/// Projects a cursor-agent user-local plugin tree that stays inside
/// `plugins/local` without exposing pool `.git` / `node_modules`.
abstract final class CursorPluginRuntimeTree {
  CursorPluginRuntimeTree._();

  static const componentDirNames = <String>[
    'skills',
    'agents',
    'commands',
    'hooks',
    'rules',
    'apps',
  ];

  static const rootFileNames = <String>[
    '.mcp.json',
    'mcp.json',
    'README.md',
    'LICENSE',
    'plugin.json',
  ];

  static Future<void> materialize({
    required Filesystem fs,
    required String sourceRoot,
    required String destRoot,
    required PluginManifestPaths paths,
  }) async {
    if ((await fs.lstat(destRoot)).exists) {
      await fs.removeRecursive(destRoot);
    }
    await fs.ensureDir(destRoot);

    final ctx = fs.pathContext;
    for (final name in _manifestDirNames(paths)) {
      final source = ctx.join(sourceRoot, name);
      if (!(await fs.stat(source)).isDirectory) continue;
      await fs.copyTree(source: source, destination: ctx.join(destRoot, name));
    }

    for (final name in componentDirNames) {
      final source = ctx.join(sourceRoot, name);
      if (!(await fs.stat(source)).exists) continue;
      await CliPluginLayout.linkOrCopyTree(
        fs: fs,
        source: source,
        destination: ctx.join(destRoot, name),
      );
    }

    for (final name in rootFileNames) {
      final source = ctx.join(sourceRoot, name);
      if (!(await fs.stat(source)).isFile) continue;
      await fs.copyFile(source, ctx.join(destRoot, name));
    }
  }

  static Set<String> _manifestDirNames(PluginManifestPaths paths) => {
    paths.manifestDirName,
    if (paths.fallbackManifestDirName != null) paths.fallbackManifestDirName!,
    neutralPluginManifestPaths.manifestDirName,
    claudePluginManifestPaths.manifestDirName,
    cursorPluginManifestPaths.manifestDirName,
  };
}
