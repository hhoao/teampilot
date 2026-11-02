import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../registry/capabilities/mcp_capability.dart';
import '../../registry/mcp_writers/metadata_mcp_merge.dart';

/// Antigravity global MCP config: `<configDir>/mcp_config.json`
/// (`{"mcpServers": {…}}`), merged so unrelated top-level keys survive.
final class AntigravityMcpCapability implements McpCapability {
  const AntigravityMcpCapability();

  static const metadataFileName = 'mcp_config.json';

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
  }) {
    return mergeMetadataMcpServers(
      fs: fs,
      configDir: configDir,
      metadataFileName: metadataFileName,
      servers: servers,
    );
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {}

  /// Antigravity reads only the global `mcp_config.json`, so there is no
  /// project-scoped teammate-bus entry to remove.
  @override
  Future<void> maybeRemoveStaleProjectTeammateBus({
    required Filesystem fs,
    Map<String, Map<String, Object?>>? extraServers,
    required String workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) async {}
}
