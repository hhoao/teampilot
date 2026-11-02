import '../../../io/filesystem.dart';

/// Projects a neutral `.plugin/plugin.json` bundle onto Antigravity's native
/// plugin layout:
///
/// ```
/// <targetDir>/plugin.json      <- .plugin/plugin.json (or .claude-plugin/)
/// <targetDir>/skills/          <- bundle skills/
/// <targetDir>/agents/          <- bundle agents/
/// <targetDir>/rules/           <- bundle rules/
/// <targetDir>/mcp_config.json  <- .plugin/.mcp.json (or .mcp.json)
/// <targetDir>/hooks.json       <- .plugin/hooks.json (or hooks.json)
/// ```
///
/// Antigravity reads a plugin manifest at the plugin root (not inside a hidden
/// `.plugin/` directory), so the manifest is hoisted and MCP/hook fragments are
/// renamed to Antigravity's `mcp_config.json` / `hooks.json`.
final class AntigravityPluginProjector {
  const AntigravityPluginProjector._();

  /// Component directories copied verbatim when present in the bundle.
  static const componentDirs = ['skills', 'agents', 'rules'];

  static Future<void> project({
    required Filesystem fs,
    required String bundleDir,
    required String targetDir,
  }) async {
    final ctx = fs.pathContext;
    if ((await fs.stat(targetDir)).exists) {
      await fs.removeRecursive(targetDir);
    }
    await fs.ensureDir(targetDir);

    final manifest =
        await fs.readString(ctx.join(bundleDir, '.plugin', 'plugin.json')) ??
        await fs.readString(
          ctx.join(bundleDir, '.claude-plugin', 'plugin.json'),
        );
    if (manifest != null) {
      await fs.writeString(ctx.join(targetDir, 'plugin.json'), manifest);
    }

    for (final name in componentDirs) {
      final src = ctx.join(bundleDir, name);
      if ((await fs.stat(src)).isDirectory) {
        await fs.copyTree(
          source: src,
          destination: ctx.join(targetDir, name),
        );
      }
    }

    final mcp =
        await fs.readString(ctx.join(bundleDir, '.plugin', '.mcp.json')) ??
        await fs.readString(ctx.join(bundleDir, '.mcp.json'));
    if (mcp != null) {
      await fs.writeString(ctx.join(targetDir, 'mcp_config.json'), mcp);
    }

    final hooks =
        await fs.readString(ctx.join(bundleDir, '.plugin', 'hooks.json')) ??
        await fs.readString(ctx.join(bundleDir, 'hooks.json'));
    if (hooks != null) {
      await fs.writeString(ctx.join(targetDir, 'hooks.json'), hooks);
    }
  }
}
