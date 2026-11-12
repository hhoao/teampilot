import 'dart:convert';

import '../../../io/filesystem.dart';

/// Projects a neutral `.plugin/plugin.json` bundle onto Grok's plugin layout:
///
/// ```
/// <targetDir>/plugin.json          <- .plugin/plugin.json (or .claude-plugin/)
/// <targetDir>/.plugin/plugin.json  <- same manifest, for member inspection
/// <targetDir>/skills/              <- bundle skills/
/// <targetDir>/commands/            <- bundle commands/
/// <targetDir>/agents/              <- bundle agents/
/// <targetDir>/.mcp.json            <- .plugin/.mcp.json (or .mcp.json)
/// <targetDir>/hooks/hooks.json     <- .plugin/hooks.json (or hooks/hooks.json)
/// ```
///
/// Grok discovers components from these standard directories when no manifest
/// overrides them; a root `plugin.json` is optional. The hidden `.plugin`
/// manifest copy keeps [PluginManifestPaths] based inspection working.
final class GrokPluginProjector {
  const GrokPluginProjector._();

  static const componentDirs = ['skills', 'commands', 'agents'];

  static bool isSafeDirName(String name) {
    if (name.isEmpty || name == '.' || name == '..') return false;
    if (name.contains('/') || name.contains('\\')) return false;
    return true;
  }

  static Future<String?> project({
    required Filesystem fs,
    required String bundleDir,
    required String targetDir,
  }) async {
    final ctx = fs.pathContext;
    if (!isSafeDirName(ctx.basename(targetDir))) {
      throw ArgumentError.value(
        targetDir,
        'targetDir',
        'unsafe plugin directory name',
      );
    }
    if ((await fs.stat(targetDir)).exists) {
      await fs.removeRecursive(targetDir);
    }
    await fs.ensureDir(targetDir);

    final manifest =
        await fs.readString(ctx.join(bundleDir, '.plugin', 'plugin.json')) ??
        await fs.readString(
          ctx.join(bundleDir, '.claude-plugin', 'plugin.json'),
        );
    String? manifestName;
    if (manifest != null) {
      await fs.atomicWrite(ctx.join(targetDir, 'plugin.json'), manifest);
      await fs.atomicWrite(
        ctx.join(targetDir, '.plugin', 'plugin.json'),
        manifest,
      );
      manifestName = _manifestName(manifest);
    }

    for (final name in componentDirs) {
      final src = ctx.join(bundleDir, name);
      if ((await fs.stat(src)).isDirectory) {
        await fs.copyTree(source: src, destination: ctx.join(targetDir, name));
      }
    }

    final mcp =
        await fs.readString(ctx.join(bundleDir, '.plugin', '.mcp.json')) ??
        await fs.readString(ctx.join(bundleDir, '.mcp.json'));
    if (mcp != null) {
      await fs.atomicWrite(ctx.join(targetDir, '.mcp.json'), mcp);
    }

    final hooks =
        await fs.readString(ctx.join(bundleDir, '.plugin', 'hooks.json')) ??
        await fs.readString(ctx.join(bundleDir, 'hooks', 'hooks.json'));
    if (hooks != null) {
      final target = ctx.join(targetDir, 'hooks', 'hooks.json');
      await fs.ensureDir(ctx.dirname(target));
      await fs.atomicWrite(target, hooks);
    }
    return manifestName;
  }

  static String? _manifestName(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final name = decoded['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    } on FormatException {
      // Optional manifest: a malformed file still leaves the bundle usable.
    }
    return null;
  }
}
