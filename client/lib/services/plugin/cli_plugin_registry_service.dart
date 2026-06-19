import 'dart:convert';

import '../../models/plugin.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/capabilities/plugin_manifest_paths.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../provider/cursor/cursor_session_config_dir.dart';
import 'claude_flavor_registry_writer.dart';
import 'cli_plugin_layout.dart';
import '../io/filesystem.dart';

/// Session-scoped facade for [ClaudeFlavorRegistryWriter].
///
/// Loads the installed catalog from TeamPilot app data and delegates registry
/// writes to the shared Claude-flavor writer.
class CliPluginRegistryService {
  CliPluginRegistryService({
    required this.fs,
    required this.teampilotRoot,
    RuntimeLayout? layout,
    CliToolRegistry? cliRegistry,
    ClaudeFlavorRegistryWriter? registryWriter,
  }) : _layout = layout ?? RuntimeLayout(teampilotRoot: teampilotRoot, fs: fs),
       _cliRegistry = cliRegistry ?? CliToolRegistry.builtIn(),
       _writer = registryWriter ??
           ClaudeFlavorRegistryWriter(
             fs: fs,
             teampilotRoot: teampilotRoot,
           );

  final Filesystem fs;
  final String teampilotRoot;
  final RuntimeLayout _layout;
  final CliToolRegistry _cliRegistry;
  final ClaudeFlavorRegistryWriter _writer;

  static String? _cachedCatalogPath;
  static int? _cachedCatalogMtimeMs;
  static List<Plugin>? _cachedCatalog;
  static const _cursorLocalPluginsSegment = 'local';

  /// After bundles are copied into the member tool dir, register them for the CLI.
  Future<void> writeForSession({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    required CliTool tool,
    TeamProfile? team,
    String? memberId,
    List<Plugin>? installedCatalog,
    String? memberProvisionJson,
  }) async {
    final paths = _pathsForTool(tool);
    if (paths == null) return;
    final poolDir = _layout.sessionRuntimePluginsDir(
      workspaceId,
      sessionId,
      tool.value,
      memberId: memberId,
    );
    final configDir = _sessionConfigDir(
      tool: tool,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
    );
    await _writePluginRegistry(
      configDir: configDir,
      memberPluginsDir: await _memberPluginsDirForRegistry(
        tool: tool,
        configDir: configDir,
        poolDir: poolDir,
      ),
      tool: tool,
      enabledIds: team?.pluginIds ?? const <String>[],
      installedCatalog: installedCatalog,
      memberProvisionJson: memberProvisionJson,
      paths: paths,
    );
  }

  /// Registers plugins for a standalone personal workspace session CONFIG_DIR.
  Future<void> writeForStandaloneSession({
    required String workspaceId,
    required String sessionId,
    required CliTool tool,
    PersonalProfile? personal,
    List<Plugin>? installedCatalog,
    String? memberProvisionJson,
  }) async {
    final paths = _pathsForTool(tool);
    if (paths == null) return;
    final poolDir = _layout.sessionRuntimePluginsDir(
      workspaceId,
      sessionId,
      tool.value,
    );
    final configDir = _sessionConfigDir(
      tool: tool,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    await _writePluginRegistry(
      configDir: configDir,
      memberPluginsDir: await _memberPluginsDirForRegistry(
        tool: tool,
        configDir: configDir,
        poolDir: poolDir,
      ),
      tool: tool,
      enabledIds: personal?.bundle.pluginIds ?? const <String>[],
      installedCatalog: installedCatalog,
      memberProvisionJson: memberProvisionJson,
      paths: paths,
    );
  }

  /// Registers plugins from a [PluginProvisionContext] (capability-driven).
  Future<void> writeFromProvisionContext(
    PluginProvisionContext ctx, {
    required PluginManifestPaths paths,
  }) async {
    await _writePluginRegistry(
      configDir: ctx.configDir,
      memberPluginsDir: ctx.bundlePoolDir,
      tool: ctx.tool,
      enabledIds: ctx.enabledPluginIds,
      installedCatalog: ctx.installedCatalog,
      memberProvisionJson: ctx.memberProvisionJson,
      paths: paths,
    );
  }

  Future<void> _writePluginRegistry({
    required String configDir,
    required String memberPluginsDir,
    required CliTool tool,
    required List<String> enabledIds,
    required PluginManifestPaths paths,
    List<Plugin>? installedCatalog,
    String? memberProvisionJson,
  }) async {
    final catalog = installedCatalog ?? await _loadInstalledCatalog();
    await _writer.write(
      configDir: configDir,
      memberPluginsDir: memberPluginsDir,
      tool: tool,
      enabledIds: enabledIds,
      paths: paths,
      catalog: catalog,
      memberProvisionJson: memberProvisionJson,
    );
  }

  Future<List<Plugin>> _loadInstalledCatalog() async {
    final path = AppPaths.pluginsJsonForTeampilotRoot(teampilotRoot);
    final stat = await fs.stat(path);
    final mtimeMs = stat.mtime?.millisecondsSinceEpoch ?? 0;
    if (_cachedCatalogPath == path &&
        _cachedCatalogMtimeMs == mtimeMs &&
        _cachedCatalog != null) {
      return _cachedCatalog!;
    }

    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) {
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = const [];
      return _cachedCatalog!;
    }
    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      final catalog = (root['plugins'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
          .toList();
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = catalog;
      return catalog;
    } catch (_) {
      _cachedCatalogPath = path;
      _cachedCatalogMtimeMs = mtimeMs;
      _cachedCatalog = const [];
      return _cachedCatalog!;
    }
  }

  PluginManifestPaths? _pathsForTool(CliTool tool) =>
      pluginProvisionerForTool(tool, registry: _cliRegistry)?.manifestPaths;

  String _sessionConfigDir({
    required CliTool tool,
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) {
    if (tool == CliTool.cursor) {
      return CursorSessionConfigDir.resolve(
        _layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return _layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      tool.value,
      memberId: memberId,
    );
  }

  Future<String> _memberPluginsDirForRegistry({
    required CliTool tool,
    required String configDir,
    required String poolDir,
  }) async {
    if (tool != CliTool.cursor) return poolDir;
    final paths = cursorPluginManifestPaths;
    final localDir = fs.pathContext.join(
      configDir,
      'plugins',
      _cursorLocalPluginsSegment,
    );
    final poolStat = await fs.stat(poolDir);
    if (!poolStat.isDirectory) {
      await fs.ensureDir(localDir);
      return localDir;
    }

    await fs.ensureDir(localDir);
    final ctx = fs.pathContext;
    for (final entry in await fs.listDir(poolDir)) {
      if (entry.name.startsWith('.')) continue;
      final source = ctx.join(poolDir, entry.name);
      if (!await CliPluginLayout.isPluginBundleEntry(fs, source)) continue;
      final root = await CliPluginLayout.resolvePluginRoot(
        fs,
        source,
        paths: paths,
      );
      if (root == null) continue;

      final dirName = await CliPluginLayout.bundleDirName(
        fs,
        root,
        paths: paths,
      );
      final dest = ctx.join(localDir, dirName);
      if ((await fs.stat(dest)).exists) {
        await fs.removeRecursive(dest);
      }
      await fs.copyTree(source: root, destination: dest);
      await CliPluginLayout.projectBundleToFlavor(fs, dest, paths);
    }
    return localDir;
  }
}
