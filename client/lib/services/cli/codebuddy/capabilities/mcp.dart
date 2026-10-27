import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../registry/capabilities/mcp_capability.dart';
import '../../registry/mcp_writers/metadata_mcp_merge.dart';
import '../../claude/capabilities/mcp_project_cleanup.dart' as project_mcp;

/// CodeBuddy global MCP config: `<CODEBUDDY_CONFIG_DIR>/mcp.json`
/// (`{"mcpServers": {…}}`), the same shape as the project `.mcp.json`.
final class CodebuddyMcpCapability implements McpCapability {
  const CodebuddyMcpCapability();

  static const metadataFileName = 'mcp.json';

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

  @override
  Future<void> maybeRemoveStaleProjectTeammateBus({
    required Filesystem fs,
    Map<String, Map<String, Object?>>? extraServers,
    required String workingDirectory,
    Iterable<String> additionalDirectories = const [],
  }) {
    return project_mcp.maybeRemoveStaleProjectTeammateBus(
      fs: fs,
      extraServers: extraServers,
      projectRoots: project_mcp.projectMcpRootsFromLaunch(
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
      ),
    );
  }
}
