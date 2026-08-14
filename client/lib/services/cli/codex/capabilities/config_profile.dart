import '../../../../models/app_provider_config.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../registry/cli_tool_registry.dart';
import '../provider/codex_auth_artifacts.dart';
import '../../../mcp/mcp_credentials_store.dart';
import 'provider.dart';
import '../provider/codex_home_provisioner.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../provider/codex_official_provider.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/provider_catalog_access.dart';
import '../provider/codex_provider_settings_resolver.dart';
import '../provider/codex_managed_hook_overlay.dart';
import '../provider/codex_hook_writer.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../../utils/logging/logger.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../../utils/workspace/trusted_project_paths.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import 'prompt.dart';

/// Codex CLI launch: provisions provider `auth.json` + `config.toml` under
/// per-member [CODEX_HOME], optional team-bus overlay in mixed mode, and
/// member identity in `AGENTS.md`.
final class CodexConfigProfileCapability implements ConfigProfileCapability {
  const CodexConfigProfileCapability({
    this.promptProvision = const CodexPromptCapability(),
  });

  static const toolId = 'codex';

  final PromptCapability promptProvision;

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
      // Managed hooks (team-bus Stop → /idle, agent-status lifecycle) come
      // from the completer; rendered together with user hooks in ONE pass.
      // Agent-status hooks: simple + team whenever stamped — not mixed-gated.
      final agentStatus = ctx.agentStatus;
      final managedEntries = <HookEntry>[
        if (busIdle != null && member != null && member.isValid)
          ...const HookSeatContextCompleter().busIdleHooks(
            idle: busIdle,
            memberId: member.id,
          ),
        if (agentStatus != null && member != null && member.isValid)
          ...const HookSeatContextCompleter().agentStatusHooks(
            endpoint: agentStatus,
            memberId: member.id,
          ),
      ];
      final allEntries = [...managedEntries, ...ctx.hooks];
      if (allEntries.isNotEmpty) {
        final writer = const CodexHookWriter();
        final hooksDir = paths.joinWork(codexHome, 'hooks');
        final result = writer.render(
          entries: allEntries,
          ctx: HookRenderContext(
            hooksDir: hooksDir,
            runner: host.scriptRunner,
            glueBuilder: const GlueScriptBuilder(),
          ),
        );
        for (final script in result.scripts) {
          await paths.fs.atomicWrite(
            paths.joinWork(hooksDir, script.fileName),
            script.content,
          );
        }
        final fragment = result.configFragments['config.toml'] as String?;
        if (fragment != null && fragment.trim().isNotEmpty) {
          overlayParts.add(fragment);
        }
        for (final warning in result.warnings) {
          appLogger.d('[hook-writer] codex $warning');
        }
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

    await promptProvision.materialize(
      PromptMaterializeContext(
        paths: paths,
        scope: ctx.scope,
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ),
    );

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

  static String _resolveCodexEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required AppProviderConfig provider,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = CodexProviderCapability();
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
