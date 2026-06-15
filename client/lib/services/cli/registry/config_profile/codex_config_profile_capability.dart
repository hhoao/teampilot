import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/project_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/codex/codex_auth_artifacts.dart';
import '../../../provider/codex/codex_effort_capability.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../capabilities/cli_effort_capability.dart';
import '../../../provider/codex/codex_official_provider.dart';
import '../../../provider/codex/codex_provider_settings_resolver.dart';
import '../../../provider/codex/codex_team_bus_overlay.dart';
import '../../../session/member_role_provision.dart';
import '../capabilities/config_profile_capability.dart';

/// Codex CLI launch: provisions provider `auth.json` + `config.toml` under
/// per-member [CODEX_HOME], optional team-bus overlay in mixed mode, and
/// member identity in `AGENTS.md`.
final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability();

  static const toolId = 'codex';
  static const agentsFileName = 'AGENTS.md';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final standalone = ctx.standaloneScope;
    final profile = ctx.profile;
    if (standalone != null && profile != null) {
      return _contributeStandaloneLaunch(ctx, standalone, profile);
    }

    final paths = ctx.paths;
    final codexHome = paths.sessionToolDir(
      ctx.scope.teamId,
      ctx.scope.sessionId,
      toolId,
    );

    final member = ctx.member;
    final team = ctx.team;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    await paths.fs.ensureDir(codexHome);

    if (team != null) {
      final resolver = CodexProviderSettingsResolver(
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
        warnings.add('codex_provider_missing');
      } else {
        final port = mixed ? _parseBusPort(ctx.busIdleUrl) : null;
        final busOverlay =
            mixed && port != null && member != null && member.isValid
            ? CodexTeamBusOverlay.build(memberId: member.id, port: port)
            : null;
        final trustedDirectories = <String>[
          if ((ctx.workingDirectory ?? '').trim().isNotEmpty)
            ctx.workingDirectory!.trim(),
          for (final dir in ctx.additionalDirectories)
            if (dir.trim().isNotEmpty) dir.trim(),
        ];
        try {
          await CodexHomeProvisioner(fs: paths.fs).provision(
            codexHome: codexHome,
            provider: provider,
            busOverlayToml: busOverlay,
            trustedProjectDirectories: trustedDirectories,
            storedAuthPath: _storedCodexAuthPath(paths, provider),
            reasoningEffortOverride: _resolveCodexEffort(
              team: team,
              member: member,
              provider: provider,
            ),
          );
        } on CodexHomeProvisionException catch (e) {
          warnings.add('codex_config_invalid: $e');
        }
      }
    } else {
      warnings.add('codex_provider_missing');
    }

    if (member != null && member.isValid) {
      final prompt = MemberRoleProvision.composeRolePrompt(
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ).trim();
      if (prompt.isNotEmpty) {
        await paths.fs.atomicWrite(
          paths.pathContext.join(codexHome, agentsFileName),
          '$prompt\n',
        );
      }
    }

    return ConfigProfileLaunchContribution(
      environment: {'CODEX_HOME': codexHome},
      warnings: warnings,
    );
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
    ProjectProfile profile,
  ) async {
    final paths = ctx.paths;
    final member = standaloneMemberFromProfile(profile, preset: null);
    final codexHome = standaloneSessionToolDir(paths, standalone, toolId);
    final warnings = <String>[];

    await paths.fs.ensureDir(codexHome);

    final resolver = CodexProviderSettingsResolver(
      basePath: paths.basePath,
      repository: AppProviderRepository(
        basePath: paths.basePath,
        fs: paths.fs,
      ),
    );
    var provider = await resolver.findById(standaloneProviderId(ctx.preset));
    provider ??= await _resolveSoleCodexProvider(paths);
    if (provider == null) {
      warnings.add('codex_provider_missing');
    } else {
      final trustedDirectories = <String>[
        if ((ctx.workingDirectory ?? '').trim().isNotEmpty)
          ctx.workingDirectory!.trim(),
        for (final dir in ctx.additionalDirectories)
          if (dir.trim().isNotEmpty) dir.trim(),
      ];
      try {
        await CodexHomeProvisioner(fs: paths.fs).provision(
          codexHome: codexHome,
          provider: provider,
          trustedProjectDirectories: trustedDirectories,
          storedAuthPath: _storedCodexAuthPath(paths, provider),
          reasoningEffortOverride: _resolveCodexEffort(
            team: null,
            member: member,
            provider: provider,
            profileEffort: '', // TODO: migrate to presets — profile.agent.effort / profile.effortsByTool
          ),
        );
      } on CodexHomeProvisionException catch (e) {
        warnings.add('codex_config_invalid: $e');
      }
    }

    if (member.isValid) {
      final prompt = MemberRoleProvision.composeRolePrompt(
        member: member,
        mixed: false,
      ).trim();
      if (prompt.isNotEmpty) {
        await paths.fs.atomicWrite(
          paths.pathContext.join(codexHome, agentsFileName),
          '$prompt\n',
        );
      }
    }

    return ConfigProfileLaunchContribution(
      environment: {'CODEX_HOME': codexHome},
      warnings: warnings,
    );
  }

  Future<AppProviderConfig?> _resolveSoleCodexProvider(
    ConfigProfileDelegate paths,
  ) async {
    final providers = await AppProviderRepository(
      basePath: paths.basePath,
      fs: paths.fs,
    ).loadProviders(CliTool.codex);
    if (providers.length == 1) return providers.first;
    return null;
  }

  /// Back-compat for tests that target the team-bus overlay fragment only.
  @visibleForTesting
  static String buildCodexConfigToml({
    required String memberId,
    required int port,
  }) =>
      CodexTeamBusOverlay.build(memberId: memberId, port: port);

  static int? _parseBusPort(String? idleUrl) {
    if (idleUrl == null || idleUrl.isEmpty) return null;
    final uri = Uri.tryParse(idleUrl);
    if (uri == null || !uri.hasPort) return null;
    return uri.port;
  }

  static String _resolveCodexEffort({
    required TeamConfig? team,
    required TeamMemberConfig? member,
    required AppProviderConfig provider,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = CodexEffortCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.codex,
      context: EffortResolveContext(
        team: team,
        member: member,
        provider: provider,
        model: member?.model.isNotEmpty == true
            ? member!.model
            : provider.defaultModel,
      ),
    );
  }

  static String? _storedCodexAuthPath(
    ConfigProfileDelegate paths,
    AppProviderConfig provider,
  ) {
    if (!isOfficialCodexOAuthProvider(provider)) return null;
    return paths.pathContext.join(
      paths.basePath,
      'providers',
      'codex',
      provider.id,
      CodexAuthArtifacts.authFileName,
    );
  }
}
