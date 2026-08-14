import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../../registry/capabilities/mcp_capability.dart';
import 'config_profile.dart';
import '../../flashskyai/capabilities/config_profile.dart';
import '../../registry/mcp_writers/metadata_mcp_merge.dart';

/// Merges MCP servers into `<configDir>/.claude.json` `mcpServers`.
final class ClaudeMcpCapability implements McpCapability {
  const ClaudeMcpCapability();

  static const metadataFileName =
      ClaudeConfigProfileCapability.metadataFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {
    await mergeMetadataMcpServers(
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
  }) async {
    await McpCredentialsStore(fs: fs).mergeInto(
      fromConfigDir: appConfigDir,
      toConfigDir: sessionConfigDir,
      fallbackFromConfigDir: fallbackAppConfigDir,
    );
  }
}

/// Merges MCP servers into `<configDir>/.flashskyai.json` `mcpServers`.
final class FlashskyaiMcpCapability implements McpCapability {
  const FlashskyaiMcpCapability();

  static const metadataFileName =
      FlashskyaiConfigProfileCapability.metadataFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {
    await mergeMetadataMcpServers(
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
  }) async {
    await McpCredentialsStore(fs: fs).mergeInto(
      fromConfigDir: appConfigDir,
      toConfigDir: sessionConfigDir,
      fallbackFromConfigDir: fallbackAppConfigDir,
    );
  }
}
