import 'dart:convert';

import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../capabilities/mcp_config_writer_capability.dart';
import 'claude_shape_mcp_json.dart';

/// Writes `<cursorConfigDir>/mcp.json` with Claude-shaped `mcpServers`.
final class CursorMcpConfigWriter implements McpConfigWriterCapability {
  const CursorMcpConfigWriter();

  static const mcpFileName = 'mcp.json';

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
  }) async {
    final mcpPath = fs.pathContext.join(configDir, mcpFileName);
    final stat = await fs.stat(mcpPath);
    Map<String, Object?> existing;
    if (stat.isFile) {
      final text = await fs.readString(mcpPath);
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

    await fs.ensureDir(fs.pathContext.dirname(mcpPath));
    await fs.atomicWrite(
      mcpPath,
      const JsonEncoder.withIndent('  ').convert(existing),
    );
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {
    await McpCredentialsStore(fs: fs).mergeInto(
      fromConfigDir: appConfigDir,
      toConfigDir: sessionConfigDir,
      fallbackFromConfigDir: fallbackAppConfigDir,
    );
  }
}
