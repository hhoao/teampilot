import 'package:flutter/foundation.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../models/credential_action_result.dart';
import '../../../../models/credential_probe.dart';
import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../../services/provider/credential_binding.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../io/filesystem.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/passthrough_provider_form_capability.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../remote/remote_credential_materializer.dart';
import '../../../session/member_role_provision.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../claude/provider/claude_effort_catalog.dart';
import '../../registry/capabilities/claude_family_hook_registry.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/hook/managed_hook_provisioner.dart';
import '../../registry/prompt/prompt_hub_service.dart';
import '../../../resource/providers/endpoint_hook_contribution_provider.dart';
import '../../../resource/providers/extension_hook_contribution_provider.dart';
import '../../../resource/providers/hook_library_contribution_provider.dart';
import '../../../resource/providers/managed_hook_contribution_provider.dart';
import '../../../resource/providers/hook_contribution_provider.dart';
import '../provider/flashskyai_live_import.dart';
import '../provider_presets.dart';

/// Flashskyai provider 全栈:目录/表单/模型/effort(无凭证概念)。
final class FlashskyaiProviderCapability extends CatalogModelCapability
    with PassthroughProviderFormDefaults
    implements ProviderCapability {
  const FlashskyaiProviderCapability();

  // ---- ProviderCatalogCapability ----
  @override
  CliTool get catalogCli => CliTool.flashskyai;

  @override
  String? get defaultOfficialProviderId => null;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => FlashskyaiLiveImport.loadSnapshot(context);

  // ---- ProviderDisplayCapability ----
  @override
  bool get hasModelPanel => true;
  @override
  bool get showModelCount => true;
  @override
  bool get supportsDelegate => true;
  @override
  bool get supportsOAuthCredentials => false;
  @override
  bool get usesLlmConfigJsonPreview => true;

  // ---- ProviderFormCapability ----
  @override
  List<AppProviderPreset> get presets => FlashskyaiProviderPresets.all;

  @override
  Map<String, Object?> defaultConfig() => {'provider_type': 'openai'};

  @override
  String defaultApiKeyField() => 'api_key';

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
    AppProviderConfig? provider,
    String? executable,
    bool forceRefresh = false,
  }) async {}

  // ---- Credential concept (flashskyai has none) ----
  @override
  bool appliesTo(AppProviderConfig provider) => false;

  @override
  List<ProviderCredentialActionSpec> actionsFor(AppProviderConfig provider) =>
      const [];

  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async =>
      CredentialProbe(
        providerId: provider.id,
        status: CredentialStatus.missing,
        credentialPath: '',
      );

  @override
  Future<CredentialActionResult> execute({
    required String providerId,
    required ProviderCredentialActionKind kind,
    ProviderCredentialActionInput input = const ProviderCredentialActionInput(),
  }) async => CredentialActionResult.serviceUnavailable();

  @override
  bool hidesApiKeyFields(AppProviderConfig provider) => false;

  @override
  @override
  bool get supportsCredentialBinding => false;

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
  }) async => null;

  // ---- CliEffortCapability ----
  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({AppProviderConfig? provider}) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.hidden;

  @override
  bool isApplicable({required String model}) =>
      ClaudeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) => ClaudeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({required String model, AppProviderConfig? provider}) =>
      ClaudeEffortCatalog.defaultLevel;

  // ---- Session-home materialization (formerly FlashskyaiConfigProfileCapability) ----

  static const toolId = 'flashskyai';
  static const metadataFileName = '.flashskyai.json';
  static const settingsFileName = 'settings.json';
  static const configDirEnvKey = 'FLASHSKYAI_CONFIG_DIR';
  static const sessionHomeDirEnvKey = 'FLASHSKYAI_SESSION_HOME_DIR';

  static const defaultMetadata = <String, Object?>{
    'hasCompletedOnboarding': true,
    // Follow the embedded terminal's light/dark out of the box (no `/theme`),
    // resolved from the COLORFGBG we inject at launch. Seed-only: a later user
    // `/theme` choice is persisted and wins via `{...defaults, ...existing}`.
    // See ClaudeProviderCapability.defaultMetadata for the rationale.
    'theme': 'auto',
  };

  static const defaultProjectConfig = <String, Object?>{
    'hasTrustDialogAccepted': true,
    'hasCompletedProjectOnboarding': true,
    'projectOnboardingSeenCount': 1,
    'allowedTools': <Object?>[],
    'mcpServers': <String, Object?>{},
  };

  static String sessionMetadataFile(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) => delegate.joinWork(
    delegate.sessionToolDir(workspaceId, sessionId, toolId, memberId: memberId),
    metadataFileName,
  );

  @override
  Future<SessionHomeContribution> materializeSessionHome(
    SessionHomeContext ctx,
  ) async {
    final delegate = ctx.paths;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final warnings = <String>[];

    await delegate.layout.ensureAppToolLayout(toolId);
    await _ensureSessionDefaults(
      delegate,
      scope.workspaceId,
      scope.sessionId,
      memberId: scope.memberId,
    );

    await _provisionWorkspaceTrust(
      delegate: delegate,
      workspaceId: scope.workspaceId,
      workingDirectory: workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );

    if (ctx.crossMachine) {
      final copied =
          await CrossMachineCredentialBridge.materializeFlashskyaiLlmConfig(
            catalog: ctx.catalog,
            work: delegate,
          );
      if (!copied) {
        warnings.add('flashskyai_llm_config_missing');
      }
    }
    await _writeMetadata(
      delegate,
      scope,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );

    final appendPromptEnv = await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      team: ctx.team,
      members: ctx.members,
      launchedMember: ctx.member,
      forceTeamLeadDelegateMode: ctx.team?.forceTeamLeadDelegateMode ?? false,
      mixed: ctx.team?.teamMode == TeamMode.mixed,
      simple: ctx.isSimple,
      busIdle: ctx.busIdle,
      agentStatus: ctx.agentStatus,
      effortLevel: _resolveFlashskyaiEffort(
        team: ctx.team,
        member: ctx.member,
        model: presetModelId(ctx.preset).isNotEmpty
            ? presetModelId(ctx.preset)
            : (ctx.member?.model ?? ''),
        profileEffort: ctx.preset?.effort ?? '',
      ),
      userHooks: ctx.hooks,
      hookLibraryProvider: ctx.hookLibraryProvider,
      resourceHookProviders: ctx.resourceProviders.hooks,
      promptAlreadyMaterialized: ctx.promptAlreadyMaterialized,
    );

    final environment = <String, String>{
      ..._teamLaunchEnvironment(delegate, scope),
      ...appendPromptEnv,
    };
    return SessionHomeContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<void> _ensureSessionDefaults(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId, {
    String? memberId,
  }) async {
    await _ensureSessionDefaultsAt(
      delegate,
      delegate.sessionToolDir(
        workspaceId,
        sessionId,
        toolId,
        memberId: memberId,
      ),
    );
  }

  Future<void> _ensureSessionDefaultsAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
  ) async {
    final file = delegate.joinWork(memberToolDir, metadataFileName);
    final existing = await delegate.readMetadataFile(file, defaultMetadata);
    await delegate.writeJsonIfChanged(file, {...defaultMetadata, ...existing});
  }

  Future<void> _provisionWorkspaceTrust({
    required ConfigProfileDelegate delegate,
    required String workspaceId,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) {
    return WorkspaceTrustProvisioner(
      layout: delegate.layout,
      fs: delegate.fs,
    ).provisionWorkspace(
      workspaceId: workspaceId,
      directories: [
        if (workingDirectory.trim().isNotEmpty) workingDirectory.trim(),
        for (final directory in additionalDirectories)
          if (directory.trim().isNotEmpty) directory.trim(),
      ],
      tools: const [FlashskyaiProviderCapability.toolId],
    );
  }

  Future<Map<String, String>> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    bool simple = false,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    required String effortLevel,
    List<HookEntry> userHooks = const [],
    HookContributionProvider? hookLibraryProvider,
    Iterable<HookContributionProvider> resourceHookProviders = const [],
    bool promptAlreadyMaterialized = false,
  }) async {
    final selected = launchedMember;
    if (selected == null || !selected.isValid) {
      await _writeTeamSettings(delegate, scope, effortLevel: effortLevel);
      return const {};
    }
    final appendPromptEnv = <String, String>{};
    await _writeMemberProfile(
      delegate: delegate,
      scope: scope,
      member: selected,
      launchedMember: launchedMember,
      appendPromptEnv: appendPromptEnv,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
      simple: simple,
      busIdle: busIdle,
      agentStatus: agentStatus,
      effortLevel: effortLevel,
      userHooks: userHooks,
      hookLibraryProvider: hookLibraryProvider,
      resourceHookProviders: resourceHookProviders,
      promptAlreadyMaterialized: promptAlreadyMaterialized,
    );
    return appendPromptEnv;
  }

  Future<void> _writeTeamSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope, {
    required String effortLevel,
  }) async {
    final file = delegate.joinWork(
      delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
      settingsFileName,
    );
    final teamDefaults = _teamSettings(effortLevel: effortLevel);
    if (await _settingsAlreadyCurrent(delegate, file, teamDefaults)) {
      return;
    }
    var merged = await _teamSettingsMerged(
      delegate,
      file,
      effortLevel: effortLevel,
    );
    // Task 18 收敛：无 member 的 team settings 路径同样把扩展 settings-hook
    // 并入统一 writer 渲染（旧 applyExtensionSettings 写盘合并已删除）。
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final extensionHooks = await delegate.extensionSettingsHooks(
      memberToolDir,
      tool: toolId,
      teamId: scope.teamId,
    );
    const completer = HookSeatContextCompleter();
    final assembledHooks = await completer.assemble(
      cli: CliTool.flashskyai,
      providers: [
        if (extensionHooks.isNotEmpty)
          ExtensionHookContributionProvider(settingsHooks: extensionHooks),
      ],
    );
    final entries = assembledHooks.entries;
    final hookWriter = CliToolRegistry.builtIn().capability<HookCapability>(
      CliTool.flashskyai,
    );
    if (hookWriter != null && entries.isNotEmpty) {
      final hooksDir = delegate.joinWork(memberToolDir, 'hooks');
      final result =
          await ManagedHookProvisioner(
            fs: delegate.fs,
            joinWork: delegate.joinWork,
            logPrefix: '[hook-writer] flashskyai',
          ).provision(
            writer: hookWriter,
            entries: entries,
            ctx: HookRenderContext(
              hooksDir: hooksDir,
              runner: delegate.hostEnvironmentForProvision().scriptRunner,
              glueBuilder: const GlueScriptBuilder(),
            ),
          );
      merged = mergeHooksInto(
        merged,
        (result.configFragments['settings.json'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
    }
    await delegate.writeJsonIfChanged(file, merged);
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required TeamMemberConfig? launchedMember,
    required Map<String, String> appendPromptEnv,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    bool simple = false,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    required String effortLevel,
    List<HookEntry> userHooks = const [],
    HookContributionProvider? hookLibraryProvider,
    Iterable<HookContributionProvider> resourceHookProviders = const [],
    required bool promptAlreadyMaterialized,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    if (!promptAlreadyMaterialized) {
      final promptContribution = await const PromptHubService().provisionForCli(
        cli: CliTool.flashskyai,
        ctx: PromptMaterializeContext(
          paths: delegate,
          scope: scope,
          member: member,
          forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
          mixed: mixed,
          additionalDirectories: const [],
        ),
      );
      if (promptContribution.written && member.id == launchedMember?.id) {
        appendPromptEnv.addAll(promptContribution.environment);
      }
    }
    final settingsFile = delegate.joinWork(memberToolDir, settingsFileName);
    var settings = _memberSettings(member, effortLevel: effortLevel);
    settings = MemberRoleProvision.applyTeamSessionPolicy(
      settings,
      mixed: mixed,
    );
    // 收敛：agent-status / team-lead delegate / 扩展 settings-hook / bus idle
    // 都先以 neutral HookEntry 进入 Provider → HookAssembler；FlashskyAI
    // 的 bus-idle entry 随后由本 capability 还原为 exit-2 command hook。
    const completer = HookSeatContextCompleter();
    final delegateCommand = await delegate.resolveTeamLeadDelegateHookCommand(
      member,
      memberToolDir,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
    );
    final extensionHooks = await delegate.extensionSettingsHooks(
      memberToolDir,
      tool: toolId,
      teamId: simple ? null : scope.teamId,
      workspaceId: simple ? scope.workspaceId : null,
    );
    final assembledHooks = await completer.assemble(
      cli: CliTool.flashskyai,
      member: member,
      providers: [
        if (mixed && busIdle != null)
          BusIdleHookContributionProvider(
            endpoint: busIdle,
            memberId: member.id,
          ),
        if (agentStatus != null)
          AgentStatusHookContributionProvider(
            endpoint: agentStatus,
            memberId: member.id,
          ),
        if (delegateCommand != null)
          ManagedHookContributionProvider(
            entries: completer.delegateHooks(commands: [delegateCommand]),
            providerId: 'team-lead-delegate',
          ),
        if (extensionHooks.isNotEmpty)
          ExtensionHookContributionProvider(settingsHooks: extensionHooks),
        ...resourceHookProviders.where(
          (provider) => provider.providerId != 'user-library',
        ),
        hookLibraryProvider ?? UserHookContributionProvider(entries: userHooks),
      ],
    );
    final entries = assembledHooks.entries;
    final hookWriter = CliToolRegistry.builtIn().capability<HookCapability>(
      CliTool.flashskyai,
    );
    if (hookWriter != null && entries.isNotEmpty) {
      final hooksDir = delegate.joinWork(memberToolDir, 'hooks');
      final result =
          await ManagedHookProvisioner(
            fs: delegate.fs,
            joinWork: delegate.joinWork,
            logPrefix: '[hook-writer] flashskyai',
          ).provision(
            writer: hookWriter,
            entries: entries,
            ctx: HookRenderContext(
              hooksDir: hooksDir,
              runner: delegate.hostEnvironmentForProvision().scriptRunner,
              glueBuilder: const GlueScriptBuilder(),
              generatedScriptDirectory: memberToolDir,
            ),
          );
      settings = mergeHooksInto(
        settings,
        (result.configFragments['settings.json'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
    }
    settings = await delegate.maybeApplyTeamLeadHooks(
      settings,
      member,
      memberToolDir,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
    );
    await delegate.writeSettingsFile(
      settingsFile,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: simple ? null : scope.teamId,
      workspaceId: simple ? scope.workspaceId : null,
    );
  }

  Future<bool> _settingsAlreadyCurrent(
    ConfigProfileDelegate delegate,
    String path,
    Map<String, Object?> teamDefaults,
  ) async {
    if (!(await delegate.fs.stat(path)).isFile) return false;
    final existing = await delegate.readSettingsFile(path);
    for (final entry in teamDefaults.entries) {
      if (entry.key == 'enabledPlugins') continue;
      if (existing[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<Map<String, Object?>> _teamSettingsMerged(
    ConfigProfileDelegate delegate,
    String path, {
    required String effortLevel,
  }) async {
    final existing = await delegate.readSettingsFile(path);
    final merged = Map<String, Object?>.from(
      _teamSettings(effortLevel: effortLevel),
    );
    final enabledPlugins = existing['enabledPlugins'];
    if (enabledPlugins is Map && enabledPlugins.isNotEmpty) {
      merged['enabledPlugins'] = enabledPlugins;
    }
    return merged;
  }

  static Map<String, Object?> _teamSettings({required String effortLevel}) {
    return <String, Object?>{
      'skipDangerousModePermissionPrompt': true,
      if (effortLevel.isNotEmpty) 'effortLevel': effortLevel,
    };
  }

  static Map<String, Object?> _memberSettings(
    TeamMemberConfig member, {
    required String effortLevel,
  }) {
    return Map<String, Object?>.from(_teamSettings(effortLevel: effortLevel));
  }

  static String _resolveFlashskyaiEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required String model,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = FlashskyaiProviderCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.flashskyai,
      context: EffortResolveContext(team: team, member: member, model: model),
    );
  }

  Future<void> _writeMetadata(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = sessionMetadataFile(
      delegate,
      scope.workspaceId,
      scope.sessionId,
      memberId: scope.memberId,
    );
    final directories = [workingDirectory, ...additionalDirectories];
    if (await delegate.trustedProjectsAlreadyCurrent(
      metadataPath,
      directories,
      defaultMetadata: defaultMetadata,
    )) {
      return;
    }
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultProjectConfig: defaultProjectConfig,
      directories: directories,
    );
    await delegate.writeJsonIfChanged(metadataPath, metadata);
  }

  Map<String, String> _teamLaunchEnvironment(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
  ) {
    final memberDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    return {
      configDirEnvKey: memberDir,
      sessionHomeDirEnvKey: memberDir,
      'LLM_CONFIG_PATH': delegate.layout.appFlashskyaiLlmConfigFile,
      'FLASHSKYAI_CODE_NO_FLICKER': '1',
    };
  }
}

final _emptyCatalogUpdates = _EmptyListenable();

final class _EmptyListenable implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
