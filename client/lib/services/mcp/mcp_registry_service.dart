import 'dart:convert';

import '../../models/mcp_registry_source.dart';
import '../storage/runtime_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../cli/registry/config_profile/claude_config_profile_capability.dart';
import '../cli/registry/config_profile/flashskyai_config_profile_capability.dart';
import 'mcp_credentials_store.dart';
import 'mcp_registry_config_service.dart';
import 'smithery_mcp_auth.dart';

/// Merges team MCP catalog into member CLI global metadata files.
class McpRegistryService {
  McpRegistryService({
    required this.layout,
    Filesystem? fs,
    McpRegistryConfigService? registryConfigService,
  }) : _fs = fs ?? LocalFilesystem(),
       _registryConfigService = registryConfigService ??
           McpRegistryConfigService(
             fs: fs,
             teampilotRoot: layout.teampilotRoot,
           );

  final RuntimeLayout layout;
  final Filesystem _fs;
  final McpRegistryConfigService _registryConfigService;

  Future<void> writeForSession({
    required String projectId,
    required String teamId,
    required String sessionId,
    String? memberId,
    Map<String, Map<String, Object?>>? extraServers,
  }) async {
    final trimmedProjectId = projectId.trim();
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedProjectId.isEmpty ||
        trimmedTeamId.isEmpty ||
        trimmedSessionId.isEmpty) {
      return;
    }

    Map<String, Map<String, Object?>>? catalogServers;
    final snapshotPath = layout.identityMcpServersFile(trimmedTeamId);
    final snapshotStat = await _fs.stat(snapshotPath);
    if (snapshotStat.isFile) {
      final snapshotText = await _fs.readString(snapshotPath);
      if (snapshotText != null && snapshotText.trim().isNotEmpty) {
        final snapshotRoot =
            (jsonDecode(snapshotText) as Map).cast<String, Object?>();
        catalogServers = (snapshotRoot['mcpServers'] as Map?)
            ?.cast<String, Object?>()
            .map(
              (key, value) => MapEntry(
                key,
                value is Map ? value.cast<String, Object?>() : <String, Object?>{},
              ),
            );
      }
    }

    final mergedServers = <String, Map<String, Object?>>{};
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
    if (mergedServers.isEmpty) return;

    await _mergeForTool(
      projectId: trimmedProjectId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      tool: 'claude',
      metadataFileName: ClaudeConfigProfileCapability.metadataFileName,
      catalogServers: mergedServers,
    );
    await _mergeForTool(
      projectId: trimmedProjectId,
      sessionId: trimmedSessionId,
      memberId: memberId,
      tool: 'flashskyai',
      metadataFileName: FlashskyaiConfigProfileCapability.metadataFileName,
      catalogServers: mergedServers,
    );

    if (catalogServers != null && catalogServers.isNotEmpty) {
      await McpCredentialsStore(fs: _fs).mergeInto(
        fromConfigDir: layout.appToolRoot('claude'),
        toConfigDir: layout.sessionRuntimeToolDir(
          trimmedProjectId,
          trimmedSessionId,
          'claude',
          memberId: memberId,
        ),
      );
    }
  }

  Future<void> writeForStandaloneProject({
    required String projectId,
    required String sessionId,
    Map<String, Map<String, Object?>>? extraServers,
  }) async {
    final trimmedProjectId = projectId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedProjectId.isEmpty || trimmedSessionId.isEmpty) return;

    Map<String, Map<String, Object?>>? catalogServers;
    final snapshotPath = layout.projectConfigMcpServersFile(trimmedProjectId);
    final snapshotStat = await _fs.stat(snapshotPath);
    if (snapshotStat.isFile) {
      final snapshotText = await _fs.readString(snapshotPath);
      if (snapshotText != null && snapshotText.trim().isNotEmpty) {
        final snapshotRoot =
            (jsonDecode(snapshotText) as Map).cast<String, Object?>();
        catalogServers = (snapshotRoot['mcpServers'] as Map?)
            ?.cast<String, Object?>()
            .map(
              (key, value) => MapEntry(
                key,
                value is Map ? value.cast<String, Object?>() : <String, Object?>{},
              ),
            );
      }
    }

    final mergedServers = <String, Map<String, Object?>>{};
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
    if (mergedServers.isEmpty) return;

    await _mergeForStandaloneTool(
      projectId: trimmedProjectId,
      sessionId: trimmedSessionId,
      tool: 'claude',
      metadataFileName: ClaudeConfigProfileCapability.metadataFileName,
      catalogServers: mergedServers,
    );
    await _mergeForStandaloneTool(
      projectId: trimmedProjectId,
      sessionId: trimmedSessionId,
      tool: 'flashskyai',
      metadataFileName: FlashskyaiConfigProfileCapability.metadataFileName,
      catalogServers: mergedServers,
    );

    if (catalogServers != null && catalogServers.isNotEmpty) {
      await McpCredentialsStore(fs: _fs).mergeInto(
        fromConfigDir: layout.appToolRoot('claude'),
        toConfigDir: layout.sessionRuntimeToolDir(
          trimmedProjectId,
          trimmedSessionId,
          'claude',
        ),
      );
    }
  }

  Future<void> _mergeForTool({
    required String projectId,
    required String sessionId,
    required String tool,
    required String metadataFileName,
    required Map<String, Map<String, Object?>> catalogServers,
    String? memberId,
  }) async {
    final metaPath = _fs.pathContext.join(
      layout.sessionRuntimeToolDir(
        projectId,
        sessionId,
        tool,
        memberId: memberId,
      ),
      metadataFileName,
    );
    final stat = await _fs.stat(metaPath);
    Map<String, Object?> existing;
    if (stat.isFile) {
      final text = await _fs.readString(metaPath);
      existing = text == null || text.trim().isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }

    final mergedMcp = <String, Object?>{
      ...((existing['mcpServers'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };
    for (final entry in catalogServers.entries) {
      mergedMcp[entry.key] = Map<String, Object?>.from(entry.value);
    }
    existing['mcpServers'] = mergedMcp;

    await _fs.ensureDir(_fs.pathContext.dirname(metaPath));
    await _fs.atomicWrite(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(existing),
    );
  }

  Future<void> _mergeForStandaloneTool({
    required String projectId,
    required String sessionId,
    required String tool,
    required String metadataFileName,
    required Map<String, Map<String, Object?>> catalogServers,
  }) async {
    final metaPath = _fs.pathContext.join(
      layout.sessionRuntimeToolDir(projectId, sessionId, tool),
      metadataFileName,
    );
    final stat = await _fs.stat(metaPath);
    Map<String, Object?> existing;
    if (stat.isFile) {
      final text = await _fs.readString(metaPath);
      existing = text == null || text.trim().isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }

    final mergedMcp = <String, Object?>{
      ...((existing['mcpServers'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };
    for (final entry in catalogServers.entries) {
      mergedMcp[entry.key] = Map<String, Object?>.from(entry.value);
    }
    existing['mcpServers'] = mergedMcp;

    await _fs.ensureDir(_fs.pathContext.dirname(metaPath));
    await _fs.atomicWrite(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(existing),
    );
  }
}
