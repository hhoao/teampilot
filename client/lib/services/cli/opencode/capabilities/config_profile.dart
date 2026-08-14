import '../../../../models/team_config.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import 'provider.dart';

export 'provider.dart';

/// opencode CLI launch: provisions a per-session config dir (`OPENCODE_CONFIG_DIR`)
/// holding `opencode.json` (provider credentials, member identity via `AGENTS.md`,
/// and in mixed mode the team-bus idle plugin + teammate-bus MCP server).
final class OpencodeConfigProfileCapability implements ConfigProfileCapability {
  const OpencodeConfigProfileCapability();

  static const toolId = 'opencode';
  static const opencodeConfigFileName = 'opencode.json';
  static const agentsFileName = 'AGENTS.md';

  /// opencode treats `OPENCODE_CONFIG_DIR` as its config root: it loads
  /// `opencode.json` from this dir and auto-discovers `AGENTS.md` here as a
  /// global instruction. (The bare `OPENCODE` env is an internal run marker,
  /// not a path — setting it does nothing.)
  static const configDirEnv = 'OPENCODE_CONFIG_DIR';

  /// Absolute path to the session SQLite file. OpenCode reads this via
  /// `Flag.OPENCODE_DB` ([anomalyco/opencode] `packages/core/src/database/database.ts`);
  /// there is no `OPENCODE_DATA_DIR`. Default without this is
  /// `$XDG_DATA_HOME/opencode/opencode.db`.
  static const dbPathEnv = 'OPENCODE_DB';
  static const authContentEnv = 'OPENCODE_AUTH_CONTENT';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final contribution = await const OpencodeProviderCapability()
        .materializeSessionHome(
          sessionHomeContextFromLaunch(ctx, CliTool.opencode),
        );
    return ConfigProfileLaunchContribution(
      environment: contribution.environment,
      warnings: contribution.warnings,
    );
  }
}
