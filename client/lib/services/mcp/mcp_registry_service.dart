import 'dart:convert';

import '../../models/mcp_registry_source.dart';
import '../../models/team_config.dart';
import '../cli/registry/capabilities/mcp_config_writer_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../provider/cursor/cursor_session_config_dir.dart';
import '../provider/codex/codex_session_config_dir.dart';
import '../storage/runtime_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../../models/mcp_server_spec.dart';
import 'mcp_registry_config_service.dart';
import 'smithery_mcp_auth.dart';

/// Merges team MCP catalog into member CLI native MCP config files.
class McpRegistryService {
  McpRegistryService({
    required this.layout,
    Filesystem? fs,
    McpRegistryConfigService? registryConfigService,
    CliToolRegistry? cliRegistry,
  }) : _fs = fs ?? LocalFilesystem(),
       _registryConfigService = registryConfigService ??
           McpRegistryConfigService(
             fs: fs,
             teampilotRoot: layout.teampilotRoot,
           ),
       _cliRegistry = cliRegistry ?? CliToolRegistry.builtIn();

  final RuntimeLayout layout;
  final Filesystem _fs;
  final McpRegistryConfigService _registryConfigService;
  final CliToolRegistry _cliRegistry;

  Future<void> writeForSession({
    required String workspaceId,
    required String teamId,
    required String sessionId,
    String? memberId,
    Map<String, Map<String, Object?>>? extraServers,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    final specs = await _resolveSpecs(
      snapshotPath: layout.identityMcpServersFile(trimmedTeamId),
      extraServers: extraServers,
    );
    if (specs.isEmpty) return;

    await _fanOutToAllTools(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      specs: specs,
    );

    if (await _hasCatalogSnapshot(layout.identityMcpServersFile(trimmedTeamId))) {
      await _mergeAppCredentialsForAllTools(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
        memberId: memberId,
      );
    }
  }

  Future<void> writeForStandaloneWorkspace({
    required String workspaceId,
    required String sessionId,
    Map<String, Map<String, Object?>>? extraServers,
  }) async {
    final trimmedWorkspaceId = workspaceId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedWorkspaceId.isEmpty || trimmedSessionId.isEmpty) return;

    final snapshotPath = layout.workspaceConfigMcpServersFile(trimmedWorkspaceId);
    final specs = await _resolveSpecs(
      snapshotPath: snapshotPath,
      extraServers: extraServers,
    );
    if (specs.isEmpty) return;

    await _fanOutToAllTools(
      workspaceId: trimmedWorkspaceId,
      sessionId: trimmedSessionId,
      specs: specs,
    );

    if (await _hasCatalogSnapshot(snapshotPath)) {
      await _mergeAppCredentialsForAllTools(
        workspaceId: trimmedWorkspaceId,
        sessionId: trimmedSessionId,
      );
    }
  }

  Future<List<McpServerSpec>> _resolveSpecs({
    required String snapshotPath,
    Map<String, Map<String, Object?>>? extraServers,
  }) async {
    final mergedServers = <String, Map<String, Object?>>{};
    final catalogServers = await _loadCatalogServers(snapshotPath);
    if (catalogServers != null && catalogServers.isNotEmpty) {
      final registry = await _registryConfigService.load();
      final smitheryToken =
          registry.byKind(McpRegistrySourceKind.smithery)?.apiToken;
      mergedServers.addAll(
        SmitheryMcpAuth.applyToCatalogServers(
          catalogServers,
          smitheryToken,
        ),
      );
    }
    if (extraServers != null) {
      for (final entry in extraServers.entries) {
        mergedServers[entry.key] = Map<String, Object?>.from(entry.value);
      }
    }
    return [
      for (final entry in mergedServers.entries)
        if (McpServerSpec.fromCatalogJson(entry.key, entry.value) case final spec?)
          spec,
    ];
  }

  Future<Map<String, Map<String, Object?>>?> _loadCatalogServers(
    String snapshotPath,
  ) async {
    final snapshotStat = await _fs.stat(snapshotPath);
    if (!snapshotStat.isFile) return null;
    final snapshotText = await _fs.readString(snapshotPath);
    if (snapshotText == null || snapshotText.trim().isEmpty) return null;
    final snapshotRoot =
        (jsonDecode(snapshotText) as Map).cast<String, Object?>();
    return (snapshotRoot['mcpServers'] as Map?)
        ?.cast<String, Object?>()
        .map(
          (key, value) => MapEntry(
            key,
            value is Map ? value.cast<String, Object?>() : <String, Object?>{},
          ),
        );
  }

  Future<bool> _hasCatalogSnapshot(String snapshotPath) async {
    final servers = await _loadCatalogServers(snapshotPath);
    return servers != null && servers.isNotEmpty;
  }

  Future<void> _fanOutToAllTools({
    required String workspaceId,
    required String sessionId,
    required List<McpServerSpec> specs,
    String? memberId,
  }) async {
    for (final tool in CliTool.values) {
      final writer = _cliRegistry.capability<McpConfigWriterCapability>(tool);
      if (writer == null) continue;
      final configDir = _sessionConfigDir(
        tool: tool,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );
      await writer.write(fs: _fs, configDir: configDir, servers: specs);
    }
  }

  Future<void> _mergeAppCredentialsForAllTools({
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) async {
    for (final tool in CliTool.values) {
      final writer = _cliRegistry.capability<McpConfigWriterCapability>(tool);
      if (writer == null) continue;
      await writer.mergeAppCredentials(
        fs: _fs,
        appConfigDir: layout.appToolRoot(tool.value),
        sessionConfigDir: _sessionConfigDir(
          tool: tool,
          workspaceId: workspaceId,
          sessionId: sessionId,
          memberId: memberId,
        ),
        fallbackAppConfigDir: layout.appToolRoot(CliTool.claude.value),
      );
    }
  }

  String _sessionConfigDir({
    required CliTool tool,
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) {
    if (tool == CliTool.cursor) {
      return CursorSessionConfigDir.resolve(
        layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    if (tool == CliTool.codex) {
      return CodexSessionConfigDir.resolve(
        layout,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      );
    }
    return layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      tool.value,
      memberId: memberId,
    );
  }
}
