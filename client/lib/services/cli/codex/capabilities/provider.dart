import 'package:flutter/foundation.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger.dart';
import '../../../../utils/workspace/trusted_project_paths.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../mcp/mcp_credentials_store.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../provider/codex_auth_artifacts.dart';
import '../provider/codex_effort_catalog.dart';
import '../provider/codex_home_provisioner.dart';
import '../provider/codex_hook_writer.dart';
import '../provider/codex_live_import.dart';
import '../provider/codex_managed_hook_overlay.dart';
import '../provider/codex_official_provider.dart';
import '../provider/codex_provider_credentials_service.dart';
import '../provider/codex_provider_settings_resolver.dart';
import '../provider_presets.dart';

abstract final class CodexFormExtraKeys {
  static const effort = 'effort';
}

/// Codex provider 全栈:目录/表单/模型/凭证/effort。
final class CodexProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability {
  const CodexProviderCapability({
    CodexProviderCredentialsService? credentials,
  }) : _credentials = credentials;

  final CodexProviderCredentialsService? _credentials;

  CodexProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.codex;

  @override
  String? get defaultOfficialProviderId => 'openai-official';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => CodexLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => false;
  @override
  bool get showModelCount => false;
  @override
  bool get supportsDelegate => false;
  @override
  bool get supportsOAuthCredentials => true;
  @override
  bool get usesLlmConfigJsonPreview => false;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => CodexProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'auth': <String, Object?>{}};

  @override
  String defaultApiKeyField() => 'OPENAI_API_KEY';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      CodexFormExtraKeys.effort:
          config['model_reasoning_effort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    CodexFormExtraKeys.effort:
        preset.template.config['model_reasoning_effort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort =
        input.extra[CodexFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('model_reasoning_effort');
    } else {
      config['model_reasoning_effort'] = effort;
    }
    return config;
  }

  // ---- ProviderModelCapability (record semantics) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => const [];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.isOfficial && provider.defaultModel.trim().isEmpty) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  // ---- ProviderModelCapability: live-catalog no-op ----
  @override
  Listenable get catalogUpdates => _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      isOfficialCodexOAuthProvider(provider);

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => appliesTo(provider);

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) {
    if (!appliesTo(provider)) return const [];
    return const [
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.login,
        primary: true,
        showWhenReady: false,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importGlobal,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.importFile,
      ),
      ProviderCredentialActionSpec(
        kind: ProviderCredentialActionKind.revoke,
        showWhenReady: true,
      ),
    ];
  }

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    final service = _service;
    if (service == null) {
      return CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );
    }
    return service.probe(provider.id);
  }

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async {
    final service = _service;
    if (service == null) return CredentialActionResult.serviceUnavailable();
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importFile => service.importFromFile(
        providerId,
        input.pickedPath?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        CredentialActionResult.unsupported(),
      ProviderCredentialActionKind.revoke => service.revokeCredentials(
        providerId,
      ),
    };
  }

  @override
  bool get supportsCredentialBinding => false;

  // ---- CredentialBindingCapability (no concept: fall back to isolated) ----
  @override
  CredentialBindingKind defaultBinding(AppProviderConfig provider) =>
      CredentialBindingKind.isolated;

  @override
  Map<String, Object?> withBinding(
    Map<String, Object?> config,
    CredentialBindingKind binding,
  ) => withCredentialBinding(config, binding);

  // ---- CredentialExportCapability ----
  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final path = CodexProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).credentialPath(provider.id);
    final content = await fs.readString(path);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath: '${provider.id}/${CodexAuthArtifacts.authFileName}',
      content: content,
    );
  }

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      CodexEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => CodexEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final fromProvider =
        provider?.config['model_reasoning_effort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return CodexEffortCatalog.defaultLevel;
  }

  // ---- Session-home materialization (from CodexConfigProfileCapability) ----

  static const toolId = 'codex';

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
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

    final environment = <String, String>{
      'CODEX_HOME': paths.normalizeWork(codexHome),
      ...await McpCredentialsStore(fs: paths.fs).readOAuthEnv(codexHome),
    };

    return SessionHomeContribution(
      environment: environment,
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


final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
