import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/personal_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/codex/codex_auth_artifacts.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../../../provider/codex/codex_effort_capability.dart';
import '../../../provider/codex/codex_home_provisioner.dart';
import '../capabilities/cli_effort_capability.dart';
import '../../../provider/codex/codex_official_provider.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../provider/codex/codex_provider_settings_resolver.dart';
import '../../../provider/codex/codex_team_bus_overlay.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../session/member_role_provision.dart';
import '../../../../utils/trusted_project_paths.dart';
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
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      return _contributeStandaloneLaunch(ctx, standalone, personal);
    }

    final paths = ctx.paths;
    final codexHome = paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      toolId,
      memberId: ctx.scope.memberId,
    );

    final member = ctx.member;
    final team = ctx.team;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    await paths.fs.ensureDir(codexHome);
    await _provisionWorkspaceTrust(
      paths: paths,
      workspaceId: ctx.scope.workspaceId,
      workingDirectory: ctx.workingDirectory ?? '',
      additionalDirectories: ctx.additionalDirectories,
    );

    if (team != null) {
      final resolver = _codexResolver(ctx.catalog);
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
        final trustedDirectories = await _trustedProjectDirectories(
          paths: paths,
          workingDirectory: ctx.workingDirectory ?? '',
          additionalDirectories: ctx.additionalDirectories,
        );
        try {
          if (ctx.crossMachine && isOfficialCodexOAuthProvider(provider)) {
            await CrossMachineCredentialBridge.materializeCodexAuth(
              catalog: ctx.catalog,
              work: paths,
              providerId: provider.id,
            );
          }
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
      environment: {
        'CODEX_HOME': codexHome,
        ...await McpCredentialsStore(fs: paths.fs).readOAuthEnv(codexHome),
      },
      warnings: warnings,
    );
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
    PersonalProfile personal,
  ) async {
    final paths = ctx.paths;
    final member = standaloneMemberFromPersonal(personal, preset: ctx.preset);
    final codexHome = standaloneSessionToolDir(paths, standalone, toolId);
    final warnings = <String>[];

    await paths.fs.ensureDir(codexHome);
    await _provisionWorkspaceTrust(
      paths: paths,
      workspaceId: standalone.workspaceId,
      workingDirectory: ctx.workingDirectory ?? '',
      additionalDirectories: ctx.additionalDirectories,
    );

    final resolver = _codexResolver(ctx.catalog);
    var provider = await resolver.findById(standaloneProviderId(ctx.preset));
    provider ??= await _resolveSoleCodexProvider(ctx.catalog);
    if (provider == null) {
      warnings.add('codex_provider_missing');
    } else {
      final trustedDirectories = await _trustedProjectDirectories(
        paths: paths,
        workingDirectory: ctx.workingDirectory ?? '',
        additionalDirectories: ctx.additionalDirectories,
      );
      try {
        if (ctx.crossMachine && isOfficialCodexOAuthProvider(provider)) {
          await CrossMachineCredentialBridge.materializeCodexAuth(
            catalog: ctx.catalog,
            work: paths,
            providerId: provider.id,
          );
        }
        await CodexHomeProvisioner(fs: paths.fs).provision(
          codexHome: codexHome,
          provider: provider,
          trustedProjectDirectories: trustedDirectories,
          storedAuthPath: _storedCodexAuthPath(paths, provider),
          reasoningEffortOverride: _resolveCodexEffort(
            team: null,
            member: member,
            provider: provider,
            profileEffort: ctx.preset?.effort ?? '',
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
      environment: {
        'CODEX_HOME': codexHome,
        ...await McpCredentialsStore(fs: paths.fs).readOAuthEnv(codexHome),
      },
      warnings: warnings,
    );
  }

  Future<AppProviderConfig?> _resolveSoleCodexProvider(
    ConfigProfilePaths catalog,
  ) async {
    final providers = await providerCatalogRepository(
      catalog,
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
    required TeamProfile? team,
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

  Future<void> _provisionWorkspaceTrust({
    required ConfigProfileDelegate paths,
    required String workspaceId,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) {
    return WorkspaceTrustProvisioner(
      layout: paths.layout,
      fs: paths.fs,
    ).provisionWorkspace(
      workspaceId: workspaceId,
      directories: [
        if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
        for (final directory in additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
      tools: const [CodexConfigProfileCapability.toolId],
    );
  }

  Future<List<String>> _trustedProjectDirectories({
    required ConfigProfileDelegate paths,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) async {
    final keys = await collectTrustedProjectKeys(
      fs: paths.fs,
      directories: [
        if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
        for (final directory in additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
    );
    return keys.toList(growable: false);
  }

  static CodexProviderSettingsResolver _codexResolver(
    ConfigProfilePaths catalog,
  ) =>
      CodexProviderSettingsResolver(
        basePath: catalog.basePath,
        repository: providerCatalogRepository(catalog),
      );
}
