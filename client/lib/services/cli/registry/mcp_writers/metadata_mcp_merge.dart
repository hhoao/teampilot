import 'dart:convert';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import 'claude_shape_mcp_json.dart';

Future<void> mergeMetadataMcpServers({
  required Filesystem fs,
  required String configDir,
  required String metadataFileName,
  required List<McpServerSpec> servers,
}) async {
  final metaPath = fs.pathContext.join(configDir, metadataFileName);
  final stat = await fs.stat(metaPath);
  Map<String, Object?> existing;
  if (stat.isFile) {
    final text = await fs.readString(metaPath);
    existing = text == null || text.trim().isEmpty
        ? <String, Object?>{}
        : (jsonDecode(text) as Map).cast<String, Object?>();
  } else {
    existing = <String, Object?>{};
  }

  final mergedMcp = <String, Object?>{
    ...((existing['mcpServers'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
    ...ClaudeShapeMcpJson.mcpServersMap(servers),
  };
  existing['mcpServers'] = mergedMcp;

  await fs.ensureDir(fs.pathContext.dirname(metaPath));
  await fs.atomicWrite(
    metaPath,
    const JsonEncoder.withIndent('  ').convert(existing),
  );
}
