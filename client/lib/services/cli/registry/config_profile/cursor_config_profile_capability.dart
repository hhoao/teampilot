import '../../../../models/team_config.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/cursor/cursor_home_layout.dart';
import '../../../provider/cursor/cursor_home_provisioner.dart';
import '../../../provider/cursor/cursor_launch_environment.dart';
import '../../../provider/cursor/cursor_provider_credentials_service.dart';
import '../../../provider/cursor/cursor_provider_settings_resolver.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../provider/cursor/cursor_session_config_dir.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../provider/cursor/cursor_workspace_trust_provisioner.dart';
import '../capabilities/config_profile_capability.dart';

/// Cursor CLI launch profile.
///
/// **Standalone:** isolates config under `$CURSOR_CONFIG_DIR` (auth is global /
/// keychain, shared across config dirs) and pre-trusts the workspace workspace
/// under the runtime user home.
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
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      return _contributeStandaloneLaunch(ctx, standalone);
    }
    return _contributeTeamLaunch(ctx);
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
  ) async {
    final paths = ctx.paths;
    final personal = ctx.personal;
    // Isolate under a fake `$HOME` (like mixed mode) so cursor reads the
    // session's `~/.cursor` — plugins/MCP/skills are materialized there.
    // CURSOR_CONFIG_DIR alone does NOT relocate the `.cursor` data dir.
    final toolDir = standaloneSessionToolDir(paths, standalone, toolId);
    final home = paths.pathContext.join(
      toolDir,
      CursorSessionConfigDir.homeSegment,
    );
    final layout = CursorHomeLayout(pathContext: paths.pathContext);
    final cursorDir = layout.cursorDir(home);
    await paths.fs.ensureDir(cursorDir);

    // Provision provider auth into the isolated home so cursor can authenticate
    // (real `~/.cursor` auth is no longer visible once HOME is isolated).
    if (personal != null) {
      final providerId = standaloneProviderId(ctx.preset);
      await CursorHomeProvisioner(
        fs: paths.fs,
        credentials: CursorProviderCredentialsService(
          fs: paths.fs,
          basePath: paths.basePath,
        ),
        layout: layout,
      ).provision(
        memberHome: home,
        providerId: providerId.isEmpty ? null : providerId,
        member: standaloneMemberFromPersonal(personal, preset: ctx.preset),
        busIdle: null,
        forceTeamLeadDelegateMode: false,
        mixed: false,
      );
    }

    await _provisionWorkspaceTrust(ctx: ctx, homeRoot: home);
    return ConfigProfileLaunchContribution(
      environment: CursorLaunchEnvironment.forStandalone(
        homeRoot: home,
        cursorConfigDir: cursorDir,
      ),
    );
  }

  Future<ConfigProfileLaunchContribution> _contributeTeamLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final paths = ctx.paths;
    final cursorDir = paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      toolId,
      memberId: ctx.scope.memberId,
    );
    await paths.fs.ensureDir(cursorDir);

    final team = ctx.team;
    final member = ctx.member;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    if (mixed) {
      final memberHome = paths.pathContext.join(cursorDir, 'home');
      await paths.fs.ensureDir(memberHome);

      final credentials = CursorProviderCredentialsService(
        fs: paths.fs,
        basePath: paths.basePath,
      );
      final provisioner = CursorHomeProvisioner(
        fs: paths.fs,
        credentials: credentials,
        layout: CursorHomeLayout(pathContext: paths.pathContext),
      );

      String? providerId;
      if (team != null) {
        final resolver = CursorProviderSettingsResolver(
          basePath: ctx.catalog.basePath,
          repository: providerCatalogRepository(ctx.catalog),
        );
        final provider = await resolver.resolveForLaunch(
          team: team,
          member: member,
        );
        if (provider == null) {
          warnings.add('cursor_provider_missing');
        } else {
          providerId = provider.id;
          if (ctx.crossMachine) {
            final copied =
                await CrossMachineCredentialBridge.materializeCursorCredential(
              catalog: ctx.catalog,
              work: paths,
              providerId: providerId,
            );
            if (!copied) {
              warnings.add('cursor_credentials_missing');
            }
          } else if (!(await credentials.probe(providerId)).isReady) {
            warnings.add('cursor_credentials_missing');
          }
        }
      } else {
        warnings.add('cursor_provider_missing');
      }

      final busIdle = ctx.busIdle;
      if (member != null && member.isValid && busIdle == null) {
        warnings.add('cursor_bus_idle_missing');
      }

      if (member != null && member.isValid && busIdle != null) {
        await provisioner.provision(
          memberHome: memberHome,
          providerId: providerId,
          member: member,
          busIdle: busIdle,
          forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
          mixed: true,
        );
        await _provisionWorkspaceTrust(ctx: ctx, homeRoot: memberHome);
      }

      return ConfigProfileLaunchContribution(
        environment: CursorLaunchEnvironment.forMixed(
          homeRoot: memberHome,
          useWslPaths: false,
        ),
        warnings: warnings,
      );
    }

    // Non-mixed team fallback (cursor is not native-team-launchable, so this is
    // effectively unreachable) — still HOME-isolate for consistency.
    final home = paths.pathContext.join(
      cursorDir,
      CursorSessionConfigDir.homeSegment,
    );
    final cursorConfigDir = CursorHomeLayout(
      pathContext: paths.pathContext,
    ).cursorDir(home);
    await paths.fs.ensureDir(cursorConfigDir);
    await _provisionWorkspaceTrust(ctx: ctx, homeRoot: home);
    return ConfigProfileLaunchContribution(
      environment: CursorLaunchEnvironment.forStandalone(
        homeRoot: home,
        cursorConfigDir: cursorConfigDir,
      ),
      warnings: warnings,
    );
  }

  Future<void> _provisionWorkspaceTrust({
    required ConfigProfileLaunchContext ctx,
    required String homeRoot,
  }) async {
    final directories = [
      if ((ctx.workingDirectory ?? '').trim().isNotEmpty)
        ctx.workingDirectory!.trim(),
      for (final directory in ctx.additionalDirectories)
        if (directory.trim().isNotEmpty) directory.trim(),
    ];
    if (directories.isNotEmpty) {
      await WorkspaceTrustProvisioner(
        layout: ctx.paths.layout,
        fs: ctx.paths.fs,
      ).provisionWorkspace(
        workspaceId: ctx.scope.workspaceId,
        directories: directories,
        tools: const [CursorConfigProfileCapability.toolId],
      );
    }
    await CursorWorkspaceTrustProvisioner(fs: ctx.paths.fs)
        .provisionLaunchWorkspaces(
          homeRoot: homeRoot,
          workingDirectory: ctx.workingDirectory,
          additionalDirectories: ctx.additionalDirectories,
        );
  }
}
