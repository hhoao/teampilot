import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../storage/app_storage.dart';
import '../../../storage/runtime_context.dart';
import '../../../team_bus/mcp/bus_bridge_locator.dart';
import '../../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/hook/managed_hook_provisioner.dart';
import '../../registry/prompt/prompt_hub_service.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../provider/opencode_auth_artifacts.dart';
import '../provider/opencode_data_layout.dart';
import '../provider/opencode_effort_catalog.dart';
import '../provider/opencode_live_import.dart';
import '../provider/opencode_model_catalog.dart';
import '../provider/opencode_models_service.dart';
import '../provider/opencode_provider_credentials_service.dart';
import '../provider/opencode_provider_settings_resolver.dart';
import '../provider/opencode_shared_plugin_deps.dart';
import '../provider_presets.dart';
import '../../../resource/providers/hook_library_contribution_provider.dart';
import '../../../resource/providers/hook_contribution_provider.dart';
import 'agent_status_plugin.dart';
import 'idle_plugin.dart';
import 'opencode_hook_writer.dart';

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
    OpencodeProviderCredentialsService? credentials,
  }) : _modelsService = modelsService,
       _credentials = credentials;

  final OpencodeModelsService? _modelsService;
  final OpencodeProviderCredentialsService? _credentials;

  OpencodeProviderCredentialsService? get _service => _credentials;

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
  bool get supportsOAuthCredentials => true;
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

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.cli == CliTool.opencode && provider.isOfficial;

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
    final path = OpencodeProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).credentialPath(provider.id);
    final content = await fs.readString(path);
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

  static const _opencodeDataLayout = OpencodeDataLayout();

  /// Assembles profile-provided hooks before the OpenCode-specific writer.
  /// OpenCode's endpoint plugins remain target-native because its HookCapability
  /// has no native HTTP action; user/resource hooks still share the same
  /// target-neutral deduplication and validation path as the other CLIs.
  static Future<List<HookEntry>> assembleHookEntries({
    required Iterable<HookEntry> entries,
    TeamMemberConfig? member,
    HookContributionProvider? hookLibraryProvider,
    Iterable<HookContributionProvider> resourceHookProviders = const [],
  }) async {
    final result = await const HookSeatContextCompleter().assemble(
      cli: CliTool.opencode,
      supportsHttp: false,
      member: member,
      providers: [
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

    final securityPolicy =
        member?.launchSecurityPolicy ?? LaunchSecurityPolicy.fullAccess;
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
              !AppStorage.isInstalled ||
              AppStorage.context.mode == StorageBackendMode.native;
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

    // Agent-status plugin: simple + team whenever stamped — not mixed-gated.
    final agentStatus = ctx.agentStatus;
    if (agentStatus != null && member != null && member.isValid) {
      await _writeAgentStatusPlugin(paths: paths, opencodeDir: opencodeDir);
      config = mergeOpencodeAgentStatusPlugin(
        config,
        member.id,
        agentStatus.url,
        token: agentStatus.token,
        sessionId: agentStatus.sessionId,
      );
      changed = true;
    }

    if (!ctx.hooksAlreadyMaterialized) {
      // User hooks bridge: generated JS plugin (event hook + tool-keyed hooks),
      // plus glue scripts under `<opencodeDir>/hooks/` (paths referenced by the
      // plugin's execFile commands). Plugin entry merges into the `plugin`
      // array, coexisting with agent-status / idle entries (dedup by path).
      final assembledHookEntries = await assembleHookEntries(
        entries: ctx.hooks,
        member: member,
        hookLibraryProvider: ctx.hookLibraryProvider,
        resourceHookProviders: ctx.resourceProviders.hooks,
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
              ),
            );
        final fragment =
            result.configFragments['opencode.json'] as Map<String, Object?>?;
        if (fragment != null) {
          config = mergeOpencodePluginEntries(
            config,
            ((fragment['plugin'] as List?) ?? const []).map(
              (e) => e is String ? e : e.toString(),
            ),
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await paths.writeJsonIfChanged(configPath, config);
    }

    if (launchProvider != null &&
        launchProvider.isOfficial &&
        ctx.crossMachine) {
      final copied = await CrossMachineCredentialBridge.materializeOpencodeAuth(
        catalog: ctx.catalog,
        work: paths,
        providerId: launchProvider.id,
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
    final authContent = launchProvider == null
        ? null
        : await _readStoredAuthContent(paths, launchProvider);
    if (authContent != null) {
      environment[authContentEnv] = authContent;
    }

    return SessionHomeContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<String?> _readStoredAuthContent(
    ConfigProfileDelegate paths,
    AppProviderConfig provider,
  ) async {
    if (!provider.isOfficial) return null;
    final providerDir = paths.joinWork(
      paths.basePath,
      'providers',
      'opencode',
      provider.id,
    );
    final authPath = paths.normalizeWork(
      _opencodeDataLayout.providerAuthJsonPath(providerDir),
    );
    if (!(await paths.fs.stat(authPath)).isFile) return null;
    final bytes = await paths.fs.readBytes(authPath);
    final content = bytes != null
        ? utf8.decode(bytes)
        : await paths.fs.readString(authPath);
    if (content == null || content.trim().isEmpty) return null;
    if (!OpencodeAuthArtifacts.authJsonIndicatesReady(content, provider.id)) {
      return null;
    }
    return content.trim();
  }

  OpencodeProviderSettingsResolver _resolver(ConfigProfilePaths catalog) =>
      OpencodeProviderSettingsResolver(
        basePath: catalog.basePath,
        repository: providerCatalogRepository(catalog),
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

  Future<void> _writeAgentStatusPlugin({
    required ConfigProfileDelegate paths,
    required String opencodeDir,
  }) async {
    final pluginPath = paths.joinWork(
      opencodeDir,
      opencodeAgentStatusPluginFileName,
    );
    final existing = await paths.fs.readString(pluginPath);
    if (existing == opencodeAgentStatusPluginSource) {
      return;
    }
    await paths.fs.atomicWrite(pluginPath, opencodeAgentStatusPluginSource);
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
}

/// Parses bus idle URL (e.g. `http://127.0.0.1:12345/idle`) to the listening port.
@visibleForTesting
int? parseBusPortFromIdleUrl(String? idleUrl) {
  if (idleUrl == null || idleUrl.isEmpty) return null;
  final uri = Uri.tryParse(idleUrl);
  if (uri == null || !uri.hasPort) return null;
  return uri.port;
}

/// Merges opencode.json `plugin` entry for TeamBus idle reporting (mixed mode).
///
/// The gateway port is re-stamped on every connect, so any prior entry for the
/// same member (stale port) is replaced — never appended alongside.
@visibleForTesting
Map<String, Object?> mergeOpencodeIdlePlugin(
  Map<String, Object?> config,
  String memberId,
  int port, {
  String? token,
  String? sessionId,
}) {
  final pluginPath = './$opencodeIdlePluginFileName';
  final options = <String, Object?>{'member': memberId, 'port': port};
  if (sessionId != null && sessionId.isNotEmpty) {
    options['session'] = sessionId;
  }
  if (token != null && token.isNotEmpty) {
    options['token'] = token;
  }
  final entry = <Object?>[pluginPath, options];
  final plugins = List<Object?>.from((config['plugin'] as List?) ?? const [])
    ..removeWhere(
      (e) =>
          e is List &&
          e.isNotEmpty &&
          e[0] == pluginPath &&
          e.length > 1 &&
          e[1] is Map &&
          (e[1] as Map)['member'] == memberId,
    );
  plugins.add(entry);
  return {...config, 'plugin': plugins};
}

/// Merges opencode.json `plugin` entry for `/agent-status` reporting.
///
/// Install whenever [url] is stamped (simple + team) — not gated on mixed.
/// Every connect stamps a fresh gateway port, so a prior entry for the same
/// member (dead URL) is replaced instead of accumulating.
@visibleForTesting
Map<String, Object?> mergeOpencodeAgentStatusPlugin(
  Map<String, Object?> config,
  String memberId,
  String url, {
  String? token,
  String? sessionId,
}) {
  final pluginPath = './$opencodeAgentStatusPluginFileName';
  final options = <String, Object?>{'member': memberId, 'url': url};
  if (sessionId != null && sessionId.isNotEmpty) {
    options['session'] = sessionId;
  }
  if (token != null && token.isNotEmpty) {
    options['token'] = token;
  }
  final entry = <Object?>[pluginPath, options];
  final plugins = List<Object?>.from((config['plugin'] as List?) ?? const [])
    ..removeWhere(
      (e) =>
          e is List &&
          e.isNotEmpty &&
          e[0] == pluginPath &&
          e.length > 1 &&
          e[1] is Map &&
          (e[1] as Map)['member'] == memberId,
    );
  plugins.add(entry);
  return {...config, 'plugin': plugins};
}

/// Merges materialized opencode plugin entry paths (`./plugins/<name>/<rel>`)
/// into the `plugin` array. String entries are appended when absent; tuple
/// entries (`[path, options]`, e.g. the idle/agent-status plugins) are
/// preserved and matched by their leading path.
Map<String, Object?> mergeOpencodePluginEntries(
  Map<String, Object?> config,
  Iterable<String> entryPaths,
) {
  if (entryPaths.isEmpty) return config;
  final plugins = List<Object?>.from((config['plugin'] as List?) ?? const []);
  final present = <Object?>{
    for (final e in plugins)
      if (e is String) e else if (e is List && e.isNotEmpty) e.first,
  };
  var changed = false;
  for (final path in entryPaths) {
    if (present.contains(path)) continue;
    plugins.add(path);
    present.add(path);
    changed = true;
  }
  if (!changed) return config;
  return {...config, 'plugin': plugins};
}

/// opencode 工具调用超时(ms）。opencode 默认只有 30s（`DEFAULT_TIMEOUT`），长阻塞的
/// `wait_for_message` 因此很快超时。opencode 用同一个 MCP SDK，超时由 config 的
/// `timeout` 控；设大到 24h 让它不主动超时（stdio 下这是唯一上限；remote 下也把
/// 30s 提到 24h，严格改进）。对齐 claude 的 `busToolTimeoutMs`。
const opencodeBusToolTimeoutMs = 86400000; // 24h

/// Merges the teammate-bus MCP server into opencode.json `mcp` so the member can
/// send/receive teammate messages (mixed mode).
///
/// opencode uses the top-level `mcp` field (not `mcpServers`). 传 [bridgePath]
/// （本地 PTY + 桥接可用）→ `type: "local"`（stdio，经 `teammate_bus_bridge` 绕开
/// HTTP 传输超时，`wait_for_message` 真阻塞）；否则 `type: "remote"`（HTTP 回落）。
/// 两者都带 `timeout` = [opencodeBusToolTimeoutMs]，并需 `enabled` 才会启动加载。
@visibleForTesting
Map<String, Object?> mergeOpencodeTeammateBusMcp(
  Map<String, Object?> config,
  String memberId,
  int port, {
  required String sessionId,
  String? bridgePath,
}) {
  final servers = <String, Object?>{
    ...((config['mcp'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final endpoint = 'http://127.0.0.1:$port/mcp';
  servers[teammateBusMcpServerName] = bridgePath != null
      ? <String, Object?>{
          'type': 'local',
          'command': <String>[
            bridgePath,
            '--member',
            memberId,
            '--session',
            sessionId,
            '--bus-url',
            endpoint,
          ],
          'enabled': true,
          'timeout': opencodeBusToolTimeoutMs,
        }
      : <String, Object?>{
          'type': 'remote',
          'url': endpoint,
          'enabled': true,
          'headers': <String, Object?>{
            teammateBusMcpMemberHeader: memberId,
            teammateBusMcpSessionHeader: sessionId,
          },
          'timeout': opencodeBusToolTimeoutMs,
        };
  return {...config, 'mcp': servers};
}

/// Merges a provider's credentials into opencode.json `provider.<id>.options`.
///
/// opencode reads `apiKey` / `baseURL` (note the capital `URL`) from the
/// provider's `options`; an optional `npm` (from the app provider's `config`)
/// tells opencode which SDK to use for fully custom, non-catalog providers.
@visibleForTesting
Map<String, Object?> mergeOpencodeProvider(
  Map<String, Object?> config,
  AppProviderConfig provider,
) {
  final id = provider.id.trim();
  if (id.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config['provider'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[id] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  final entry = <String, Object?>{...existing};
  final options = <String, Object?>{
    ...((existing['options'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };

  final apiKey = provider.apiKey.trim();
  if (apiKey.isNotEmpty) options['apiKey'] = apiKey;
  final baseUrl = provider.baseUrl.trim();
  if (baseUrl.isNotEmpty) options['baseURL'] = baseUrl;

  final npm = provider.config['npm'];
  if (npm is String && npm.trim().isNotEmpty && entry['npm'] == null) {
    entry['npm'] = npm.trim();
  }

  // Custom openai-compatible providers need an explicit models map or
  // `--model provider/id` fails with "model not found".
  final defaultModel = provider.defaultModel.trim();
  if (defaultModel.isNotEmpty) {
    final models = <String, Object?>{
      ...((entry['models'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };
    if (!models.containsKey(defaultModel)) {
      models[defaultModel] = <String, Object?>{'name': defaultModel};
      entry['models'] = models;
    }
  }

  if (options.isNotEmpty) entry['options'] = options;
  if (entry.isEmpty) return config;

  providers[id] = entry;
  return {...config, 'provider': providers};
}

/// Writes `provider.<id>.models.<model>.options.reasoningEffort` for launch.
@visibleForTesting
Map<String, Object?> mergeOpencodeReasoningEffort(
  Map<String, Object?> config,
  AppProviderConfig provider,
  String reasoningEffort, {
  String? memberModel,
}) {
  final effort = reasoningEffort.trim();
  if (effort.isEmpty) return config;

  final providerId = provider.id.trim();
  final modelId = (memberModel?.trim().isNotEmpty ?? false)
      ? memberModel!.trim()
      : provider.defaultModel.trim();
  if (providerId.isEmpty || modelId.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config['provider'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[providerId] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  final entry = <String, Object?>{...existing};
  final models = <String, Object?>{
    ...((existing['models'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final modelEntry = <String, Object?>{
    ...((models[modelId] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final options = <String, Object?>{
    ...((modelEntry['options'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  options['reasoningEffort'] = effort;
  modelEntry['options'] = options;
  models[modelId] = modelEntry;
  entry['models'] = models;
  providers[providerId] = entry;
  return {...config, 'provider': providers};
}

/// Merges workspace additional directories into opencode.json `permission` so
/// tool calls touching paths outside the project root run without prompting.
///
/// opencode has no `--add-dir`; cross-root access is governed by the
/// `external_directory` permission (default `ask`). Each directory becomes a
/// `"<dir>/**": "allow"` pattern — the semantic equivalent of claude/codex
/// `--add-dir`. Existing `permission` / `external_directory` entries are
/// preserved and entries are idempotent.
@visibleForTesting
Map<String, Object?> mergeOpencodeExternalDirectories(
  Map<String, Object?> config,
  Iterable<String> directories,
) {
  final permission = <String, Object?>{
    ...((config['permission'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final external = <String, Object?>{
    ...((permission['external_directory'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  var changed = false;
  for (final dir in directories) {
    final t = dir.trim();
    if (t.isEmpty) continue;
    final pattern = t.endsWith('/') ? '$t**' : '$t/**';
    if (external[pattern] != 'allow') {
      external[pattern] = 'allow';
      changed = true;
    }
  }
  if (!changed) return config;
  permission['external_directory'] = external;
  return {...config, 'permission': permission};
}

/// Materializes the normalized launch security policy into OpenCode's V1
/// `permission` object. OpenCode has no hook-trust dimension, but it can
/// express the full-access tuple through edit, bash, and external-directory
/// permissions. Policies that cannot be represented are rejected by the
/// launch capability instead of inheriting OpenCode's permissive defaults.
@visibleForTesting
Map<String, Object?> mergeOpencodeSecurityPolicy(
  Map<String, Object?> config,
  LaunchSecurityPolicy policy,
) {
  if (policy == LaunchSecurityPolicy.cliDefault) return config;
  if (policy != LaunchSecurityPolicy.fullAccess) {
    throw const CliLaunchCapabilityException(
      cli: CliTool.opencode,
      contributionKey: 'opencode-permission',
      reason:
          'OpenCode cannot represent this launch security policy through its '
          'current permission config schema.',
      exclusiveGroup: 'opencode-permission-mode',
    );
  }

  final permission = <String, Object?>{
    ...((config['permission'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final external = <String, Object?>{
    ...((permission['external_directory'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
    '*': 'allow',
  };
  permission['edit'] = 'allow';
  permission['bash'] = 'allow';
  permission['external_directory'] = external;
  return {...config, 'permission': permission};
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
