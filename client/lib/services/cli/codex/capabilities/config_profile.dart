import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../registry/cli_tool_registry.dart';
import '../provider/codex_auth_artifacts.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../provider/codex_effort_capability.dart';
import '../provider/codex_home_provisioner.dart';
import '../../registry/capabilities/cli_effort_capability.dart';
import '../provider/codex_official_provider.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/provider_catalog_access.dart';
import '../provider/codex_provider_settings_resolver.dart';
import '../provider/codex_agent_status_overlay.dart';
import '../provider/codex_managed_hook_overlay.dart';
import '../provider/codex_team_bus_overlay.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../host/host_script_runner.dart';
import '../../../io/filesystem.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../../../utils/workspace/trusted_project_paths.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import 'prompt_provision.dart';

/// Codex CLI launch: provisions provider `auth.json` + `config.toml` under
/// per-member [CODEX_HOME], optional team-bus overlay in mixed mode, and
/// member identity in `AGENTS.md`.
final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability({
    this.promptProvision = const CodexPromptProvisionCapability(),
  });

  static const toolId = 'codex';

  final PromptProvisionCapability promptProvision;

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
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
    try {
      await paths.layout.ensureSessionInheritsCodexTmpPlugins(
        ctx.scope.workspaceId,
        ctx.scope.sessionId,
        memberId: ctx.scope.memberId,
      );
    } on Object catch (e) {
      warnings.add('codex_tmp_plugins: $e');
    }
    await _provisionWorkspaceTrust(
      paths: paths,
      workspaceId: ctx.scope.workspaceId,
      workingDirectory: ctx.workingDirectory ?? '',
      additionalDirectories: ctx.additionalDirectories,
    );

    final resolver = _codexResolver(ctx.catalog);
    AppProviderConfig? provider;
    if (team != null) {
      provider = await resolver.resolveForLaunch(
        team: team,
        member: member,
      );
    } else if (ctx.isSimple) {
      final required =
          member ?? (throw StateError('Simple launch requires plan.member'));
      var fromMember = required.provider.trim();
      if (fromMember.isEmpty) {
        fromMember = CliToolRegistry.builtIn().defaultOfficialProviderId(CliTool.codex) ?? '';
      }
      provider = await resolver.findById(
        fromMember,
      );
      provider ??= await _resolveSoleCodexProvider(ctx.catalog);
    }

    if (provider == null) {
      warnings.add('codex_provider_missing');
    } else {
      final busIdle = mixed ? ctx.busIdle : null;
      final host = paths.hostEnvironmentForProvision();
      final overlayParts = <String>[];
      final installsManagedHooks =
          (busIdle != null || ctx.agentStatus != null) &&
          member != null &&
          member.isValid;
      if (installsManagedHooks) {
        overlayParts.add(
          CodexManagedHookOverlay.build(
            dangerouslySkipPermissions: member.dangerouslySkipPermissions,
          ),
        );
      }
      if (busIdle != null && member != null && member.isValid) {
        overlayParts.add(
          await (busIdle.isRemote
              ? CodexTeamBusOverlay.provisionStopHook(
                  fs: paths.fs,
                  runner: host.scriptRunner,
                  codexHome: codexHome,
                  memberId: member.id,
                  idle: busIdle,
                )
              : CodexTeamBusOverlay.buildLocal(
                  fs: paths.fs,
                  runner: host.scriptRunner,
                  codexHome: codexHome,
                  memberId: member.id,
                  idle: busIdle,
                )),
        );
      }
      // Agent-status hooks: simple + team whenever stamped — not mixed-gated.
      final agentStatus = ctx.agentStatus;
      if (agentStatus != null && member != null && member.isValid) {
        overlayParts.add(
          await CodexAgentStatusOverlay.provision(
            fs: paths.fs,
            runner: host.scriptRunner,
            codexHome: codexHome,
            memberId: member.id,
            endpoint: agentStatus,
          ),
        );
      }
      final busOverlay =
          overlayParts.isEmpty ? null : overlayParts.join('\n\n');
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
            profileEffort: member?.effort ?? '',
          ),
          providerDir: paths.joinWork(
            paths.basePath,
            'providers',
            'codex',
            provider.id,
          ),
        );
      } on CodexHomeProvisionException catch (e) {
        warnings.add('codex_config_invalid: $e');
      }
    }

    final promptContribution = await promptProvision.provision(
      PromptProvisionContext(
        paths: paths,
        scope: ctx.scope,
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ),
    );
    if (promptContribution.written) {
      // AGENTS.md written; no transport env for codex.
    }

    return ConfigProfileLaunchContribution(
      environment: {
        'CODEX_HOME': paths.normalizeWork(codexHome),
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
  static Future<String> buildCodexConfigToml({
    required Filesystem fs,
    required HostScriptRunner runner,
    required String codexHome,
    required String memberId,
    required MemberBusIdleEndpoint idle,
  }) => CodexTeamBusOverlay.buildLocal(
    fs: fs,
    runner: runner,
    codexHome: codexHome,
    memberId: memberId,
    idle: idle,
  );

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
    return paths.joinWork(
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
  ) => CodexProviderSettingsResolver(
    basePath: catalog.basePath,
    repository: providerCatalogRepository(catalog),
  );
}
