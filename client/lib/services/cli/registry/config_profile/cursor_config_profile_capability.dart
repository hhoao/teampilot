import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/cursor/cursor_home_bus_overlay.dart';
import '../../../provider/cursor/cursor_home_layout.dart';
import '../../../provider/cursor/cursor_home_provisioner.dart';
import '../../../provider/cursor/cursor_launch_environment.dart';
import '../../../provider/cursor/cursor_provider_credentials_service.dart';
import '../../../provider/cursor/cursor_provider_settings_resolver.dart';
import '../capabilities/config_profile_capability.dart';

/// Cursor CLI launch profile.
///
/// **Standalone:** isolates config under `$CURSOR_CONFIG_DIR` (auth is global /
/// keychain, shared across config dirs).
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
    final profile = ctx.profile;
    if (standalone != null && profile != null) {
      final paths = ctx.paths;
      final cursorDir = standaloneSessionToolDir(paths, standalone, toolId);
      await paths.fs.ensureDir(cursorDir);
      return ConfigProfileLaunchContribution(
        environment: CursorLaunchEnvironment.forStandaloneConfigDir(cursorDir),
      );
    }

    final paths = ctx.paths;
    final cursorDir = paths.sessionToolDir(
      ctx.scope.projectId,
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
          basePath: paths.basePath,
          repository: AppProviderRepository(
            basePath: paths.basePath,
            fs: paths.fs,
          ),
        );
        final provider = await resolver.resolveForLaunch(
          team: team,
          member: member,
        );
        if (provider == null) {
          warnings.add('cursor_provider_missing');
        } else {
          providerId = provider.id;
          if (!(await credentials.probe(providerId)).isReady) {
            warnings.add('cursor_credentials_missing');
          }
        }
      } else {
        warnings.add('cursor_provider_missing');
      }

      final port = CursorHomeBusOverlay.parseBusPort(ctx.busIdleUrl);
      if (member != null && member.isValid && port == null) {
        warnings.add('cursor_bus_idle_url_missing');
      }

      if (member != null && member.isValid) {
        await provisioner.provision(
          memberHome: memberHome,
          providerId: providerId,
          member: member,
          busPort: port,
          forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
          mixed: true,
          workspacePath: ctx.workingDirectory ?? '',
        );
      }

      return ConfigProfileLaunchContribution(
        environment: CursorLaunchEnvironment.forMixed(
          homeRoot: memberHome,
          useWslPaths: false,
        ),
        warnings: warnings,
      );
    }

    return ConfigProfileLaunchContribution(
      environment: CursorLaunchEnvironment.forStandaloneConfigDir(cursorDir),
      warnings: warnings,
    );
  }
}
