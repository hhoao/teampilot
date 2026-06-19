import '../../../io/filesystem.dart';
import '../../../../models/mcp_server_spec.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../capabilities/mcp_config_writer_capability.dart';
import 'codex_toml_merge.dart';

/// Merges MCP servers into `<configDir>/config.toml` `[mcp_servers.*]`.
final class CodexMcpConfigWriter implements McpConfigWriterCapability {
  const CodexMcpConfigWriter();

  static const configFileName = CodexHomeProvisioner.configFileName;

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
  }) async {
    final configPath = fs.pathContext.join(configDir, configFileName);
    final stat = await fs.stat(configPath);
    final existing = stat.isFile ? await fs.readString(configPath) ?? '' : '';
    final merged = CodexTomlMerge.mergeMcpServers(existing, servers);
    if (merged.trim().isEmpty) return;
    await fs.ensureDir(configDir);
    await fs.atomicWrite(configPath, merged);
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {
    final store = McpCredentialsStore(fs: fs);
    final serverEnvVars = await store.mergeOAuthEnvInto(
      fromConfigDir: appConfigDir,
      toConfigDir: sessionConfigDir,
      fallbackFromConfigDir: fallbackAppConfigDir,
    );
    if (serverEnvVars.isEmpty) return;

    final configPath = fs.pathContext.join(sessionConfigDir, configFileName);
    final stat = await fs.stat(configPath);
    final existing = stat.isFile ? await fs.readString(configPath) ?? '' : '';
    final merged = CodexTomlMerge.applyBearerTokenEnvVars(
      existing,
      serverEnvVars,
    );
    if (merged.trim().isEmpty) return;
    await fs.ensureDir(sessionConfigDir);
    await fs.atomicWrite(configPath, merged);
  }
}
