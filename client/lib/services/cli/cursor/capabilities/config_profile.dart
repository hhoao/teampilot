import '../../../../models/team_config.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import 'provider.dart';

/// Cursor CLI launch profile.
///
/// **Simple:** isolates config under a fake `$HOME`, writes member identity to
/// `~/.cursor/rules/role.mdc`, and pre-trusts the workspace under the runtime
/// user home. Auth is global / keychain, shared across config dirs.
///
/// **Mixed mode:** isolates each member under a fake `HOME` with native
/// `~/.cursor/` files (rules, hooks, mcp, cli-config) — see
/// [CursorHomeProvisioner].
final class CursorConfigProfileCapability implements ConfigProfileCapability {
  const CursorConfigProfileCapability();

  static const toolId = 'cursor';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final contribution = await const CursorProviderCapability()
        .materializeSessionHome(
          sessionHomeContextFromLaunch(ctx, CliTool.cursor),
        );
    return ConfigProfileLaunchContribution(
      environment: contribution.environment,
      warnings: contribution.warnings,
    );
  }
}
