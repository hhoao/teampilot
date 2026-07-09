import '../../../../models/app_provider_config.dart';
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
import '../../../launch/work_plane_paths.dart';
import '../../../provider/cursor/cursor_workspace_trust_provisioner.dart';
import '../../session_lifecycle/cli_session_manifest_store.dart';
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
    final personal = ctx.personal!;
    final warnings = <String>[];
    // Isolate under a fake `$HOME` (like mixed mode) so cursor reads the
    // session's `~/.cursor` — plugins/MCP/skills are materialized there.
    // CURSOR_CONFIG_DIR alone does NOT relocate the `.cursor` data dir.
    final toolDir = standaloneSessionToolDir(paths, standalone, toolId);
    final home = paths.joinWork(
      toolDir,
      CursorSessionConfigDir.homeSegment,
    );
    final layout = CursorHomeLayout(pathContext: paths.workPathContext);
    final cursorDir = layout.cursorDir(home);
    await paths.fs.ensureDir(cursorDir);

    final credentials = CursorProviderCredentialsService(
      fs: paths.fs,
      basePath: paths.basePath,
    );
    final provider = await _resolveStandaloneCursorProvider(ctx);
    final providerId = provider?.id.trim() ?? '';

    // Provision provider auth into the isolated home so cursor can authenticate
    // (real `~/.cursor` auth is no longer visible once HOME is isolated).
    if (providerId.isNotEmpty && provider != null && provider.isOfficial) {
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

    await CursorHomeProvisioner(
      fs: paths.fs,
      credentials: credentials,
      layout: layout,
    ).provision(
      memberHome: home,
      providerId: providerId.isEmpty ? null : providerId,
      member: personalMemberForSession(personal, preset: ctx.preset, sessionExpertKey: ctx.sessionExpertKey, resolvedExpert: ctx.resolvedExpert),
      busIdle: null,
      forceTeamLeadDelegateMode: false,
      mixed: false,
      realHomeRoot: paths.home,
    );

    await _provisionWorkspaceTrust(ctx: ctx, homeRoot: home);
    return ConfigProfileLaunchContribution(
      environment: CursorLaunchEnvironment.forStandalone(
        homeRoot: home,
        cursorConfigDir: cursorDir,
      ),
      warnings: warnings,
    );
  }

  Future<AppProviderConfig?> _resolveStandaloneCursorProvider(
    ConfigProfileLaunchContext ctx,
  ) async {
    final resolver = CursorProviderSettingsResolver(
      basePath: ctx.catalog.basePath,
      repository: providerCatalogRepository(ctx.catalog),
    );
    var provider = await resolver.findById(standaloneProviderId(ctx.preset));
    provider ??= await resolver.findById(
      ctx.personal?.providerIdsByTool[toolId] ?? '',
    );
    if (provider != null) return provider;

    final providers = await providerCatalogRepository(
      ctx.catalog,
    ).loadProviders(CliTool.cursor);
    if (providers.length == 1) return providers.first;
    return null;
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
      final memberId = ctx.scope.memberId?.trim() ?? '';
      final teamId = team?.id.trim() ?? '';
      final memberHome = await _resolveMixedMemberHome(
        paths: paths,
        workspaceId: ctx.scope.workspaceId,
        teamId: teamId,
        memberId: memberId,
      );

      final credentials = CursorProviderCredentialsService(
        fs: paths.fs,
        basePath: paths.basePath,
      );

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
          final providerId = provider.id;
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
    final home = paths.joinWork(
      cursorDir,
      CursorSessionConfigDir.homeSegment,
    );
    final cursorConfigDir = CursorHomeLayout(
      pathContext: paths.workPathContext,
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

  Future<String> _resolveMixedMemberHome({
    required ConfigProfilePaths paths,
    required String workspaceId,
    required String teamId,
    required String memberId,
  }) async {
    final trimmedTeamId = teamId.trim();
    final trimmedMemberId = memberId.trim();
    if (trimmedTeamId.isNotEmpty) {
      final manifest = await CliSessionManifestStore(
        fs: paths.fs,
        layout: paths.layout,
      ).read(
        workspaceId: workspaceId,
        teamId: trimmedTeamId,
        tool: toolId,
      );
      final homeRoot = manifest?.members[trimmedMemberId]?.homeRoot.trim() ?? '';
      if (homeRoot.isNotEmpty) {
        final workspaceDir = paths.layout.workspace.workspaceDir(workspaceId);
        return paths.fs.pathContext.normalize(
          paths.fs.pathContext.join(workspaceDir, homeRoot),
        );
      }
    }

    final cursorDir = paths.layout.workspaceRuntimeMemberToolDir(
      workspaceId,
      trimmedTeamId,
      trimmedMemberId,
      toolId,
    );
    return paths.fs.pathContext.join(cursorDir, 'home');
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
    await CursorWorkspaceTrustProvisioner(
      fs: ctx.paths.fs,
    ).provisionLaunchWorkspaces(
      homeRoot: homeRoot,
      workingDirectory: ctx.workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
  }
}
