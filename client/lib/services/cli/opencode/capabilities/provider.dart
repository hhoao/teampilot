import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../chat/launch/staging/manifest/work_plane_paths.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/home_storage.dart';
import '../../../storage/runtime_context.dart';
import '../../../chat/team_bus/mcp/bus_bridge_locator.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/hook/managed_hook_provisioner.dart';
import '../../registry/prompt/prompt_hub_service.dart';
import '../provider/opencode_credential_kind.dart';
import '../provider/opencode_credential_materializer.dart';
import '../provider/opencode_data_layout.dart';
import '../provider/opencode_effort_catalog.dart';
import '../provider/opencode_live_import.dart';
import '../provider/opencode_model_catalog.dart';
import '../provider/opencode_models_service.dart';
import '../provider/opencode_provider_settings_resolver.dart';
import '../opencode_config.dart';
import '../provider/opencode_shared_plugin_deps.dart';
import '../provider_presets.dart';
import '../../../resource/providers/hook_library_contribution_provider.dart';
import '../../../resource/providers/hook_contribution_provider.dart';
import '../../../resource/providers/runtime_event_hook_contribution_provider.dart';
import 'awareness_plugin.dart';
import 'idle_plugin.dart';
import 'opencode_hook_writer.dart';

export '../opencode_config.dart';

abstract final class OpencodeFormExtraKeys {
  static const effort = 'effort';
}

/// OpenCode model catalog from the live models.dev fetch, falling back to the
/// built-in static [OpencodeModelCatalog] (offline / first run before fetch).
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource(this._modelsService);

  final OpencodeModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final id = provider?.id ?? providerId;
    final live = _modelsService?.modelIdsFor(providerId: id) ?? const [];
    if (live.isNotEmpty) return live;
    return OpencodeModelCatalog.knownModelsForProvider(id);
  }
}

/// OpenCode provider 全栈:目录/表单/模型(实时 models.dev)/凭证/effort。
final class OpencodeProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, RefreshableProviderModelCapability {
  const OpencodeProviderCapability({
    OpencodeModelsService? modelsService,
    this.storage,
  }) : _modelsService = modelsService;

  final OpencodeModelsService? _modelsService;

  /// Home control-plane storage injected at registry construction; decides
  /// whether the host loopback bridge exe is reachable (native backend).
  /// Null only for `const`-constructed capabilities outside the registry
  /// (tests), where the seat is treated as local-native.
  final HomeStorage? storage;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.opencode;

  @override
  String? get defaultOfficialProviderId => 'opencode';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => OpencodeLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => false;
  @override
  bool get showModelCount => false;
  @override
  bool get supportsDelegate => false;
  @override
  bool get supportsOAuthCredentials => false;
  @override
  bool get usesLlmConfigJsonPreview => false;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => OpencodeProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  @override
  Map<String, Object?> extraFromExisting(AppProviderConfig? existing) {
    final config = existing?.config ?? defaultConfig();
    return {
      OpencodeFormExtraKeys.effort: config['reasoningEffort']?.toString() ?? '',
    };
  }

  @override
  Map<String, Object?> extraFromPreset(AppProviderPreset preset) => {
    OpencodeFormExtraKeys.effort:
        preset.template.config['reasoningEffort']?.toString() ?? '',
  };

  @override
  Map<String, Object?> buildConfig(ProviderFormInput input) {
    final config = Map<String, Object?>.from(input.config);
    final effort =
        input.extra[OpencodeFormExtraKeys.effort]?.toString().trim() ?? '';
    if (effort.isEmpty) {
      config.remove('reasoningEffort');
    } else {
      config['reasoningEffort'] = effort;
    }
    return config;
  }

  // ---- ProviderModelCapability (live models.dev) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    OpencodeCatalogSource(_modelsService),
  ];

  @override
  Listenable get catalogUpdates =>
      _modelsService?.catalogUpdates ?? _emptyCatalogUpdates;

  @override
  Future<void> refreshModelCatalog({
    required String providerId,
    AppProviderConfig? provider,
    String? executable,
    bool forceRefresh = false,
  }) {
    final service = _modelsService;
    if (service == null) return Future.value();
    return service.ensureLoaded(forceRefresh: forceRefresh);
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  // ---- ProviderCredentialCapability (catalog apiKey; no CLI login flow) ----
  @override
  bool appliesTo(AppProviderConfig provider) => false;

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => false;

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) =>
      const [];

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async =>
      OpencodeCredentialMaterializer.probe(provider);

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async => CredentialActionResult.unsupported();

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
    final content = OpencodeCredentialMaterializer.authJsonContent(provider);
    if (content == null || content.trim().isEmpty) return null;
    return CredentialFile(
      relativePath: '${provider.id}/${OpencodeDataLayout.authFileName}',
      content: content,
    );
  }

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      OpencodeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => OpencodeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) {
    final fromProvider =
        provider?.config['reasoningEffort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return OpencodeEffortCatalog.defaultLevel;
  }

  // ---- Session-home materialization (formerly OpencodeConfigProfileCapability) ----

  static const toolId = 'opencode';
  static const opencodeConfigFileName = 'opencode.json';
  static const agentsFileName = 'AGENTS.md';

  /// opencode treats `OPENCODE_CONFIG_DIR` as its config root: it loads
  /// `opencode.json` from this dir and auto-discovers `AGENTS.md` here as a
  /// global instruction. (The bare `OPENCODE` env is an internal run marker,
  /// not a path — setting it does nothing.)
  static const configDirEnv = 'OPENCODE_CONFIG_DIR';

  /// Absolute path to the session SQLite file. OpenCode reads this via
  /// `Flag.OPENCODE_DB` ([anomalyco/opencode] `packages/core/src/database/database.ts`);
  /// there is no `OPENCODE_DATA_DIR`. Default without this is
  /// `$XDG_DATA_HOME/opencode/opencode.db`.
  static const dbPathEnv = 'OPENCODE_DB';
  static const authContentEnv = 'OPENCODE_AUTH_CONTENT';

  /// Assembles profile-provided hooks before the OpenCode-specific writer.
  /// OpenCode's endpoint plugins remain target-native because its HookCapability
  /// has no native HTTP action; user/resource hooks still share the same
  /// target-neutral deduplication and validation path as the other CLIs.
  static Future<List<HookEntry>> assembleHookEntries({
    required Iterable<HookEntry> entries,
    TeamMemberConfig? member,
    HookContributionProvider? hookLibraryProvider,
    RuntimeEventHookContributionProvider? runtimeEventProvider,
    Iterable<HookContributionProvider> resourceHookProviders = const [],
  }) async {
    final result = await const HookSeatContextCompleter().assemble(
      cli: CliTool.opencode,
      supportsHttp: false,
      member: member,
      providers: [
        if (runtimeEventProvider != null) runtimeEventProvider,
        ...resourceHookProviders,
        if (resourceHookProviders.isEmpty)
          hookLibraryProvider ?? UserHookContributionProvider(entries: entries),
      ],
    );
    return result.entries;
  }

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final paths = ctx.paths;
    final opencodeDir = paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      toolId,
      memberId: ctx.scope.memberId,
    );
    final team = ctx.team;
    final member = ctx.member;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    await paths.fs.ensureDir(opencodeDir);

    // Seed shared plugin deps on home/control plane (local npm), then inherit
    // into the work-plane session dir. Never npm-install on paths.fs (SFTP).
    // Seed failures become warnings so launch env (OPENCODE_DB, …) still applies.
    try {
      final depsSw = Stopwatch()..start();
      await OpencodeSharedPluginDeps(
        layout: ctx.catalog.layout,
        fs: ctx.catalog.fs,
      ).ensureSharedInstalled();
      appLogger.d(
        '[session-launch] opencode ensure-shared-plugin-deps '
        'session=${ctx.scope.sessionId} ms=${depsSw.elapsedMilliseconds}',
      );
      final inheritSw = Stopwatch()..start();
      await paths.layout.ensureSessionInheritsOpencodePluginDeps(
        ctx.scope.workspaceId,
        ctx.scope.sessionId,
        memberId: ctx.scope.memberId,
      );
      appLogger.d(
        '[session-launch] opencode inherit-plugin-deps '
        'session=${ctx.scope.sessionId} ms=${inheritSw.elapsedMilliseconds}',
      );
    } on Object catch (e) {
      warnings.add('opencode_plugin_deps: $e');
    }

    final configPath = paths.joinWork(opencodeDir, opencodeConfigFileName);
    var config = await paths.readSettingsFile(configPath);
    var changed = false;
    AppProviderConfig? launchProvider;

    if (team != null) {
      launchProvider = await _resolver(
        ctx.catalog,
      ).resolveForLaunch(team: team, member: member);
      if (launchProvider == null) {
        warnings.add('opencode_provider_missing');
      }
    } else if (ctx.isSimple) {
      final required =
          member ?? (throw StateError('Simple launch requires plan.member'));
      final resolver = _resolver(ctx.catalog);
      var fromMember = required.provider.trim();
      if (fromMember.isEmpty) {
        fromMember =
            CliToolRegistry.builtIn().defaultOfficialProviderId(
              CliTool.opencode,
            ) ??
            '';
      }
      launchProvider = await resolver.findById(fromMember);
      launchProvider ??= await resolver.resolveSole();
    }

    if (launchProvider != null) {
      config = mergeOpencodeProvider(config, launchProvider);
      final effort = _resolveOpencodeEffort(
        team: team,
        member: member,
        provider: launchProvider,
        profileEffort: member?.effort ?? '',
      );
      if (effort.isNotEmpty) {
        config = mergeOpencodeReasoningEffort(
          config,
          launchProvider,
          effort,
          memberModel: member?.model,
        );
      }
      changed = true;
    }

    final securityPolicy = LaunchSecurityPolicy.fullAccess;
    final securedConfig = mergeOpencodeSecurityPolicy(config, securityPolicy);
    if (!identical(securedConfig, config)) {
      config = securedConfig;
      changed = true;
    }

    final workDirs = <String>[
      for (final dir in ctx.additionalDirectories)
        if (dir.trim().isNotEmpty) paths.normalizeWork(dir.trim()),
    ];
    if (workDirs.isNotEmpty) {
      config = mergeOpencodeExternalDirectories(config, workDirs);
      changed = true;
    }

    if (!ctx.promptAlreadyMaterialized) {
      final promptContribution = await const PromptHubService().provisionForCli(
        cli: CliTool.opencode,
        ctx: PromptMaterializeContext(
          paths: paths,
          scope: ctx.scope,
          member: member,
          forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
          mixed: mixed,
          additionalDirectories: workDirs,
        ),
      );
      if (promptContribution.written) {
        changed = true;
      }
    }

    if (mixed && member != null && member.isValid) {
      await _writeAwarenessPlugin(paths: paths, opencodeDir: opencodeDir);
      config = mergeOpencodeBusAwarenessPlugin(
        config,
        opencodeBusAwarenessPrompt(member: member),
      );
      changed = true;
    }

    final busIdle = ctx.busIdle;
    if (mixed && busIdle != null && member != null && member.isValid) {
      final port = busIdle.port;
      if (port != null) {
        await _writeIdlePlugin(paths: paths, opencodeDir: opencodeDir);
        config = mergeOpencodeIdlePlugin(
          config,
          member.id,
          port,
          token: busIdle.token,
          sessionId: busIdle.sessionId,
        );
        if (!busIdle.isRemote) {
          final localNative =
              storage == null ||
              storage!.context.mode == StorageBackendMode.native;
          final bridgePath = localNative ? BusBridgeLocator.resolve() : null;
          config = mergeOpencodeTeammateBusMcp(
            config,
            member.id,
            port,
            sessionId: busIdle.sessionId ?? ctx.sessionId,
            bridgePath: bridgePath,
          );
        }
        changed = true;
      } else {
        warnings.add('opencode_bus_idle_port_missing');
      }
    }

    // Runtime events are represented as HookEntry values and rendered through
    // the same assembler and HookCapability writer as user/resource hooks.
    final agentStatus = ctx.agentStatus;
    final runtimeEventProvider =
        agentStatus != null && member != null && member.isValid
        ? RuntimeEventHookContributionProvider(
            endpoint: agentStatus,
            memberId: member.id,
          )
        : null;

    if (!ctx.hooksAlreadyMaterialized || runtimeEventProvider != null) {
      // User hooks bridge: generated JS plugin (event hook + tool-keyed hooks),
      // plus glue scripts under `<opencodeDir>/hooks/` (paths referenced by the
      // plugin's execFile commands). Plugin entry merges into the `plugin`
      // array, coexisting with agent-status / idle entries (dedup by path).
      final assembledHookEntries = await assembleHookEntries(
        entries: ctx.hooksAlreadyMaterialized ? const [] : ctx.hooks,
        member: member,
        hookLibraryProvider: ctx.hooksAlreadyMaterialized
            ? null
            : ctx.hookLibraryProvider,
        runtimeEventProvider: runtimeEventProvider,
        resourceHookProviders: ctx.hooksAlreadyMaterialized
            ? const []
            : ctx.resourceProviders.hooks,
      );
      if (assembledHookEntries.isNotEmpty) {
        final writer = const OpencodeHookWriter();
        final hooksDir = paths.joinWork(opencodeDir, 'hooks');
        final result =
            await ManagedHookProvisioner(
              fs: paths.fs,
              joinWork: paths.joinWork,
              pathContext: paths.workPathContext,
              atomicWrite: true,
              ensureParentDirs: true,
              logPrefix: '[hook-writer] opencode',
              targetOverride: (fileName) =>
                  fileName == opencodeUserHooksPluginFileName
                  ? paths.joinWork(opencodeDir, fileName)
                  : null,
            ).provision(
              writer: writer,
              entries: assembledHookEntries,
              ctx: HookRenderContext(
                hooksDir: hooksDir,
                runner: paths.hostEnvironmentForProvision().scriptRunner,
                glueBuilder: const GlueScriptBuilder(),
                generatedScriptDirectory: opencodeDir,
              ),
            );
        final fragment =
            result.configFragments['opencode.json'] as Map<String, Object?>?;
        if (fragment != null) {
          config = mergeOpencodePluginEntries(
            config,
            ((fragment[opencodePluginsKey] as List?) ?? const []),
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await paths.writeJsonIfChanged(configPath, config);
    }

    if (launchProvider != null &&
        OpencodeCredentialKindResolver.needsCredential(launchProvider) &&
        ctx.crossMachine) {
      final copied = await CrossMachineCredentialBridge.materializeOpencodeAuth(
        catalog: ctx.catalog,
        work: paths,
        provider: launchProvider,
      );
      if (!copied) {
        warnings.add('opencode_credentials_missing');
      }
    }

    final normalizedOpencodeDir = paths.normalizeWork(opencodeDir);
    final environment = <String, String>{
      configDirEnv: normalizedOpencodeDir,
      // Absolute OPENCODE_DB → Database.Path (anomalyco/opencode).
      dbPathEnv: paths.normalizeWork(
        paths.pathContext.join(opencodeDir, 'opencode.db'),
      ),
    };
    if (launchProvider != null) {
      final authContent = _authContentForLaunch(launchProvider);
      if (authContent != null) {
        environment[authContentEnv] = authContent;
      } else if (OpencodeCredentialKindResolver.needsCredential(
        launchProvider,
      )) {
        warnings.add('opencode_credentials_missing');
      }
    }

    return SessionHomeContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  String? _authContentForLaunch(AppProviderConfig provider) =>
      OpencodeCredentialMaterializer.authJsonContent(provider);

  OpencodeProviderSettingsResolver _resolver(ConfigProfilePaths catalog) =>
      OpencodeProviderSettingsResolver(
        basePath: catalog.basePath,
        storage: storage ?? _missingHomeStorage(),
        repository: providerCatalogRepository(
          catalog,
          storage: storage ?? _missingHomeStorage(),
        ),
      );

  Future<void> _writeIdlePlugin({
    required ConfigProfileDelegate paths,
    required String opencodeDir,
  }) async {
    final pluginPath = paths.joinWork(opencodeDir, opencodeIdlePluginFileName);
    final existing = await paths.fs.readString(pluginPath);
    if (existing == opencodeIdlePluginSource) {
      return;
    }
    await paths.fs.atomicWrite(pluginPath, opencodeIdlePluginSource);
  }

  Future<void> _writeAwarenessPlugin({
    required ConfigProfileDelegate paths,
    required String opencodeDir,
  }) async {
    final pluginPath = paths.joinWork(
      opencodeDir,
      opencodeAwarenessPluginFileName,
    );
    final existing = await paths.fs.readString(pluginPath);
    if (existing == opencodeAwarenessPluginSource) {
      return;
    }
    await paths.fs.atomicWrite(pluginPath, opencodeAwarenessPluginSource);
  }

  static String _resolveOpencodeEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required AppProviderConfig provider,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = OpencodeProviderCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.opencode,
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

  HomeStorage _missingHomeStorage() {
    throw StateError(
      'OpencodeProviderCapability was constructed without HomeStorage; storage use requires the '
      'registry configured with CliBootstrap(storage: …).',
    );
  }
}

/// Parses bus idle URL (e.g. `http://127.0.0.1:12345/idle`) to the listening port.
@visibleForTesting
int? parseBusPortFromIdleUrl(String? idleUrl) {
  if (idleUrl == null || idleUrl.isEmpty) return null;
  final uri = Uri.tryParse(idleUrl);
  if (uri == null || !uri.hasPort) return null;
  return uri.port;
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
