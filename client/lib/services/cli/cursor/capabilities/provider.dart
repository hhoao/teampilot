import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/team_config.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../io/filesystem.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../../resource/providers/endpoint_hook_contribution_provider.dart';
import '../../../resource/providers/hook_library_contribution_provider.dart';
import '../../session_lifecycle/cli_session_manifest_store.dart';
import '../provider/cursor_agent_models_service.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_home_provisioner.dart';
import '../provider/cursor_launch_environment.dart';
import '../provider/cursor_live_import.dart';
import '../provider/cursor_provider_credentials_service.dart';
import '../provider/cursor_provider_settings_resolver.dart';
import '../provider/cursor_session_config_dir.dart';
import '../provider/cursor_windows_home_junction.dart';
import '../provider/cursor_workspace_trust_provisioner.dart';
import '../provider_presets.dart';

/// Live `cursor-agent models` catalog (cached per provider account).
final class CursorAgentCatalogSource implements ModelCatalogSource {
  const CursorAgentCatalogSource(this._modelsService);

  final CursorAgentModelsService? _modelsService;

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) => _modelsService?.modelIdsFor(providerId: providerId) ?? const [];
}

/// Cursor provider 全栈:目录/表单/模型(实时目录)/凭证/导出。
final class CursorProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability, RefreshableProviderModelCapability {
  const CursorProviderCapability({
    CursorAgentModelsService? modelsService,
    CursorProviderCredentialsService? credentials,
  }) : _modelsService = modelsService,
       _credentials = credentials;

  final CursorAgentModelsService? _modelsService;
  final CursorProviderCredentialsService? _credentials;

  CursorProviderCredentialsService? get _service => _credentials;

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.cursor;

  @override
  String? get defaultOfficialProviderId => 'cursor-account';

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => CursorLiveImport.loadSnapshot(context);

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
  List<AppProviderPreset> get presets => CursorProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => const {};

  @override
  String defaultApiKeyField() => 'api_key';

  // ---- ProviderModelCapability (live `cursor-agent models`) ----
  @override
  bool get supportsModelTiers => false;

  @override
  List<ModelCatalogSource> get catalogSources => [
    CursorAgentCatalogSource(_modelsService),
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
    return service.ensureLoaded(
      providerId: providerId,
      executable: executable,
      forceRefresh: forceRefresh,
    );
  }

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) =>
      ProviderModelPickerMode.catalogWithCustomEntry;

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    final fromAgent =
        _modelsService?.defaultModelIdFor(providerId: providerId).trim() ?? '';
    if (fromAgent.isNotEmpty) return fromAgent;
    return resolveDefaultProviderModel(
      this,
      provider: provider,
      providerId: providerId,
    );
  }

  // ---- ProviderCredentialCapability ----
  @override
  bool appliesTo(AppProviderConfig provider) =>
      provider.cli == CliTool.cursor && provider.isOfficial;

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
        kind: ProviderCredentialActionKind.importDirectory,
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
    final path = input.pickedPath?.trim() ?? '';
    return switch (kind) {
      ProviderCredentialActionKind.login => service.runAuthLogin(providerId),
      ProviderCredentialActionKind.importGlobal => service.importFromGlobal(
        providerId,
        homeDirectory: input.homeDirectory?.trim() ?? '',
        replace: input.replace,
      ),
      ProviderCredentialActionKind.importDirectory =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : _importCursorPath(
                service,
                providerId: providerId,
                path: path,
                replace: input.replace,
              ),
      ProviderCredentialActionKind.importFile =>
        path.isEmpty
            ? CredentialActionResult.failure(
                const CredentialActionFailure(
                  code: CredentialActionFailureCode.pathRequired,
                ),
              )
            : service.importAuthJsonFile(
                providerId,
                path,
                replace: input.replace,
              ),
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

  // ---- CliEffortCapability (not supported) ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.hidden;

  @override
  bool isApplicable({required String model}) => false;

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => const [];

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) =>
      '';

  // ---- CredentialExportCapability ----
  @override
  Future<CredentialFile?> exportCredential({
    required Filesystem fs,
    required String basePath,
    required String home,
    required AppProviderConfig provider,
  }) async {
    final toolRoot = fs.pathContext.join(
      basePath,
      'providers',
      provider.cli.value,
    );
    final probe = await CursorProviderCredentialsService(
      fs: fs,
      basePath: basePath,
    ).probe(provider.id);
    if (!probe.isReady) return null;
    final content = await fs.readString(probe.credentialPath);
    if (content == null || content.trim().isEmpty) return null;
    final relative = fs.pathContext.relative(
      probe.credentialPath,
      from: toolRoot,
    );
    return CredentialFile(relativePath: relative, content: content);
  }

  // ---- Session-home materialization (formerly CursorConfigProfileCapability) ----

  static const toolId = 'cursor';

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    if (ctx.isSimple) {
      return _materializeSimpleHome(ctx);
    }
    return _materializeTeamHome(ctx);
  }

  Future<SessionHomeContribution> _materializeSimpleHome(
    SessionHomeContext ctx,
  ) async {
    final paths = ctx.paths;
    final warnings = <String>[];
    // Isolate under a fake `$HOME` (like mixed mode) so cursor reads the
    // session's `~/.cursor` — plugins/MCP/skills are materialized there.
    // CURSOR_CONFIG_DIR alone does NOT relocate the `.cursor` data dir.
    final toolDir = paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      toolId,
      memberId: ctx.scope.memberId,
    );
    final canonicalHome = paths.joinWork(
      toolDir,
      CursorSessionConfigDir.homeSegment,
    );
    final home = await CursorWindowsHomeJunction.ensureAgentHome(
      fs: paths.fs,
      canonicalHome: canonicalHome,
    );
    final layout = CursorHomeLayout(pathContext: paths.workPathContext);
    final cursorDir = layout.cursorDir(home);
    await paths.fs.ensureDir(cursorDir);

    final credentials = CursorProviderCredentialsService(
      fs: paths.fs,
      basePath: paths.basePath,
    );
    final provider = await _resolveSimpleCursorProvider(ctx);
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

    final member =
        ctx.member ?? (throw StateError('Simple launch requires plan.member'));
    await CursorHomeProvisioner(
      fs: paths.fs,
      credentials: credentials,
      layout: layout,
    ).provision(
      memberHome: home,
      providerId: providerId.isEmpty ? null : providerId,
      member: member,
      busIdle: null,
      forceTeamLeadDelegateMode: false,
      mixed: false,
      // Always defer real-$HOME passthrough to SessionConnectOrchestrator after
      // manifest flush. Staging via ManifestFilesystem would SFTP-list the work
      // home (slow on Android SSH). Post-flush uses one remote find+ln script
      // when an SSH profile is available, otherwise the local FS mirror.
      realHomeRoot: null,
    );

    // 收敛：内部托管 hook（agent-status）经 completer 组装为 managed
    // HookEntry，与用户条目一次 writeHooks 落盘（同渲染 + 去重）。
    final agentStatus = ctx.agentStatus;
    final completer = const HookSeatContextCompleter();
    final assembledHooks = await completer.assemble(
      cli: CliTool.cursor,
      member: member,
      providers: [
        if (agentStatus != null)
          AgentStatusHookContributionProvider(
            endpoint: agentStatus,
            memberId: member.id,
          ),
        ctx.hookLibraryProvider ??
            UserHookContributionProvider(entries: ctx.hooks),
      ],
    );
    await CursorHomeProvisioner(
      fs: paths.fs,
      layout: CursorHomeLayout(pathContext: paths.fs.pathContext),
    ).writeHooks(
      memberHome: home,
      entries: assembledHooks.entries,
      runner: paths.hostEnvironmentForProvision().scriptRunner,
    );

    await _provisionWorkspaceTrust(ctx: ctx, homeRoot: home);
    return SessionHomeContribution(
      environment: CursorLaunchEnvironment.forStandalone(
        homeRoot: home,
        cursorConfigDir: cursorDir,
      ),
      warnings: warnings,
    );
  }

  Future<AppProviderConfig?> _resolveSimpleCursorProvider(
    SessionHomeContext ctx,
  ) async {
    final resolver = CursorProviderSettingsResolver(
      basePath: ctx.catalog.basePath,
      repository: providerCatalogRepository(ctx.catalog),
    );
    var providerId = ctx.member?.provider.trim() ?? '';
    if (providerId.isEmpty) {
      providerId =
          CliToolRegistry.builtIn().defaultOfficialProviderId(CliTool.cursor) ??
          '';
    }
    var provider = await resolver.findById(providerId);
    if (provider != null) return provider;

    final providers = await providerCatalogRepository(
      ctx.catalog,
    ).loadProviders(CliTool.cursor);
    if (providers.length == 1) return providers.first;
    return null;
  }

  Future<SessionHomeContribution> _materializeTeamHome(
    SessionHomeContext ctx,
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
      final agentHome = await CursorWindowsHomeJunction.ensureAgentHome(
        fs: paths.fs,
        canonicalHome: memberHome,
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

      final agentStatus = ctx.agentStatus;
      // 收敛：内部托管 hook（bus idle / agent-status）经 completer 组装为
      // managed HookEntry，与用户条目一次 writeHooks 落盘（同渲染 + 去重）。
      // cursor 不支持 stopFailure / permissionRequest 原生事件——writer 跳过
      // 并警告（bus stop 经 completer stop 条目生效，与旧 overlay 一致）。
      final completer = const HookSeatContextCompleter();
      final assembledHooks = await completer.assemble(
        cli: CliTool.cursor,
        member: member,
        providers: [
          if (busIdle != null && member != null && member.isValid)
            BusIdleHookContributionProvider(
              endpoint: busIdle,
              memberId: member.id,
            ),
          if (agentStatus != null && member != null && member.isValid)
            AgentStatusHookContributionProvider(
              endpoint: agentStatus,
              memberId: member.id,
            ),
          ctx.hookLibraryProvider ??
              UserHookContributionProvider(entries: ctx.hooks),
        ],
      );
      await CursorHomeProvisioner(
        fs: ctx.paths.fs,
        layout: CursorHomeLayout(pathContext: ctx.paths.fs.pathContext),
      ).writeHooks(
        memberHome: agentHome,
        entries: assembledHooks.entries,
        runner: ctx.paths.hostEnvironmentForProvision().scriptRunner,
      );

      return SessionHomeContribution(
        environment: CursorLaunchEnvironment.forMixed(
          homeRoot: agentHome,
          useWslPaths: false,
        ),
        warnings: warnings,
      );
    }

    // Non-mixed team fallback (cursor is not native-team-launchable, so this is
    // effectively unreachable) — still HOME-isolate for consistency.
    final canonicalHome = paths.joinWork(
      cursorDir,
      CursorSessionConfigDir.homeSegment,
    );
    final home = await CursorWindowsHomeJunction.ensureAgentHome(
      fs: paths.fs,
      canonicalHome: canonicalHome,
    );
    final cursorConfigDir = CursorHomeLayout(
      pathContext: paths.workPathContext,
    ).cursorDir(home);
    await paths.fs.ensureDir(cursorConfigDir);
    await _provisionWorkspaceTrust(ctx: ctx, homeRoot: home);
    return SessionHomeContribution(
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
      ).read(workspaceId: workspaceId, teamId: trimmedTeamId, tool: toolId);
      final homeRoot =
          manifest?.members[trimmedMemberId]?.homeRoot.trim() ?? '';
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
    required SessionHomeContext ctx,
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
        tools: const [CursorProviderCapability.toolId],
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

Future<CredentialActionResult> _importCursorPath(
  CursorProviderCredentialsService service, {
  required String providerId,
  required String path,
  required bool replace,
}) async {
  if (path.endsWith('auth.json')) {
    return service.importAuthJsonFile(providerId, path, replace: replace);
  }
  return service.importFromCursorDirectory(providerId, path, replace: replace);
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
