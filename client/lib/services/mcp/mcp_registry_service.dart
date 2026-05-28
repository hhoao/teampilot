import 'dart:convert';

import '../cli/cli_data_layout.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../provider/config_profile_service.dart';

/// Merges team MCP catalog into member CLI global metadata files.
class McpRegistryService {
  McpRegistryService({
    required this.layout,
    Filesystem? fs,
  }) : _fs = fs ?? LocalFilesystem();

  final CliDataLayout layout;
  final Filesystem _fs;

  Future<void> writeForSession({
    required String teamId,
    required String sessionId,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedSessionId = sessionId.trim();
    if (trimmedTeamId.isEmpty || trimmedSessionId.isEmpty) return;

    final snapshotPath = layout.teamMcpServersFile(trimmedTeamId);
    final snapshotStat = await _fs.stat(snapshotPath);
    if (!snapshotStat.isFile) return;

    final snapshotText = await _fs.readString(snapshotPath);
    if (snapshotText == null || snapshotText.trim().isEmpty) return;

    final snapshotRoot = (jsonDecode(snapshotText) as Map).cast<String, Object?>();
    final catalogServers = (snapshotRoot['mcpServers'] as Map?)
        ?.cast<String, Object?>()
        .map(
          (key, value) => MapEntry(
            key,
            value is Map ? value.cast<String, Object?>() : <String, Object?>{},
          ),
        );
    if (catalogServers == null || catalogServers.isEmpty) return;

    await _mergeForTool(
      teamId: trimmedTeamId,
      sessionId: trimmedSessionId,
      tool: 'claude',
      metadataFileName: ConfigProfileService.claudeMetadataFileName,
      catalogServers: catalogServers,
    );
    await _mergeForTool(
      teamId: trimmedTeamId,
      sessionId: trimmedSessionId,
      tool: 'flashskyai',
      metadataFileName: ConfigProfileService.flashskyaiMetadataFileName,
      catalogServers: catalogServers,
    );
  }

  Future<void> _mergeForTool({
    required String teamId,
    required String sessionId,
    required String tool,
    required String metadataFileName,
    required Map<String, Map<String, Object?>> catalogServers,
  }) async {
    final metaPath = _fs.pathContext.join(
      layout.memberToolDir(teamId, sessionId, tool),
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
