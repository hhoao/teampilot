import '../../../../models/mcp_server_spec.dart';
import '../../../io/filesystem.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../capabilities/mcp_config_writer_capability.dart';
import '../config_profile/claude_config_profile_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';
import 'metadata_mcp_merge.dart';

/// Merges MCP servers into `<configDir>/.claude.json` `mcpServers`.
final class ClaudeMcpConfigWriter implements McpConfigWriterCapability {
  const ClaudeMcpConfigWriter();

  static const metadataFileName = ClaudeConfigProfileCapability.metadataFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
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
final class FlashskyaiMcpConfigWriter implements McpConfigWriterCapability {
  const FlashskyaiMcpConfigWriter();

  static const metadataFileName =
      FlashskyaiConfigProfileCapability.metadataFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
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
