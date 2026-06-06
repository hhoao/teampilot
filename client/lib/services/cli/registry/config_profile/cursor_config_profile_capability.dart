import '../capabilities/config_profile_capability.dart';

/// Cursor CLI launch: isolates per-session config/auth/hooks under a dedicated
/// `$CURSOR_CONFIG_DIR` (the cursor-agent config-dir override). Auth itself is
/// stored globally (keychain) and shared across config dirs, so members reuse
/// the same cursor login without re-authenticating.
///
/// Phase 1 only provisions the isolated config dir. Mixed-mode team-bus idle
/// reporting (a `hooks.json` `stop` hook posting to the bus) lands in Phase 2,
/// pending verification that hooks fire in interactive TUI mode.
final class CursorConfigProfileCapability implements ConfigProfileCapability {
  const CursorConfigProfileCapability();

  static const toolId = 'cursor';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final cursorDir = ctx.paths.sessionToolDir(
      ctx.scope.teamId,
      ctx.scope.sessionId,
      toolId,
    );
    await ctx.paths.fs.ensureDir(cursorDir);

    return ConfigProfileLaunchContribution(
      environment: {'CURSOR_CONFIG_DIR': cursorDir},
    );
  }
}
