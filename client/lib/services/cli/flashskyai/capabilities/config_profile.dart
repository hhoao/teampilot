import '../../../../models/team_config.dart';
import '../../../../models/hook_entry.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import 'provider.dart';
import '../../../session/member_role_provision.dart';
import '../../registry/capabilities/provider_capability.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import 'prompt.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/capabilities/claude_family_hook_registry.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/cli_tool_registry.dart';
import 'stop_idle_hook.dart';
import '../../../../utils/logging/logger.dart';
import '../../../hook/glue_script_builder.dart';

final class FlashskyaiConfigProfileCapability
    implements ConfigProfileCapability {
  const FlashskyaiConfigProfileCapability({
    this.promptProvision = const FlashskyaiPromptCapability(),
  });

  static const toolId = 'flashskyai';
  static const metadataFileName = '.flashskyai.json';
  static const settingsFileName = 'settings.json';
  static const configDirEnvKey = 'FLASHSKYAI_CONFIG_DIR';
  static const sessionHomeDirEnvKey = 'FLASHSKYAI_SESSION_HOME_DIR';

  final PromptCapability promptProvision;

  static const defaultMetadata = <String, Object?>{
    'hasCompletedOnboarding': true,
    // Follow the embedded terminal's light/dark out of the box (no `/theme`),
    // resolved from the COLORFGBG we inject at launch. Seed-only: a later user
    // `/theme` choice is persisted and wins via `{...defaults, ...existing}`.
    // See ClaudeConfigProfileCapability.defaultMetadata for the rationale.
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
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    final delegate = ctx.paths;
    await delegate.layout.ensureAppToolLayout(toolId);
    await _ensureSessionDefaults(
      delegate,
      ctx.workspaceId,
      ctx.sessionId,
      memberId: ctx.memberId,
    );
  }

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final delegate = ctx.paths;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final warnings = <String>[];
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
    await _provisionWorkspaceTrust(
      delegate: delegate,
      workspaceId: scope.workspaceId,
      workingDirectory: workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
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
    );

    final environment = _teamLaunchEnvironment(delegate, scope);
    environment.addAll(appendPromptEnv);

    return ConfigProfileLaunchContribution(
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
    final entries = <HookEntry>[
      for (final hook in extensionHooks)
        ...completer.extensionHooks(
          extensionId: hook.extensionId,
          events: [hook.event],
          command: hook.command,
          matcher: hook.matcher,
        ),
    ];
    final hookWriter = CliToolRegistry.builtIn()
        .capability<HookCapability>(CliTool.flashskyai);
    if (hookWriter != null && entries.isNotEmpty) {
      final hooksDir = delegate.joinWork(memberToolDir, 'hooks');
      final result = hookWriter.render(
        entries: entries,
        ctx: HookRenderContext(
          hooksDir: hooksDir,
          runner: delegate.hostEnvironmentForProvision().scriptRunner,
          glueBuilder: const GlueScriptBuilder(),
        ),
      );
      for (final script in result.scripts) {
        await delegate.fs.writeString(
          delegate.joinWork(hooksDir, script.fileName),
          script.content,
        );
      }
      merged = mergeHooksInto(
        merged,
        (result.configFragments['settings.json'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
      for (final warning in result.warnings) {
        appLogger.d('[hook-writer] flashskyai $warning');
      }
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
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    final promptContribution = await promptProvision.materialize(
      PromptMaterializeContext(
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
    final settingsFile = delegate.joinWork(
      memberToolDir,
      settingsFileName,
    );
    var settings = _memberSettings(member, effortLevel: effortLevel);
    settings = MemberRoleProvision.applyTeamSessionPolicy(
      settings,
      mixed: mixed,
    );
    if (mixed && busIdle != null) {
      // HookRunner ignores HTTP decision:block; command exit 2 is required.
      final idleScriptPath = delegate.joinWork(
        memberToolDir,
        flashskyaiStopIdleScriptFileName,
      );
      await delegate.fs.writeString(
        idleScriptPath,
        flashskyaiStopIdleScript(memberId: member.id, idle: busIdle),
      );
      settings = mergeFlashskyaiStopIdleHook(settings, idleScriptPath);
    }
    // 收敛：agent-status / team-lead delegate / 扩展 settings-hook 内部托管
    // hook 经 HookSeatContextCompleter 组装为 HookEntry，与 userHooks 一起走
    // 统一 writer 渲染。
    // （flashskyai bus idle 仍走 command exit-2 脚本通道——HookRunner 忽略
    // http decision:block；Task 19 评估后保留该通道，未迁移统一 writer。）
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
    final entries = <HookEntry>[
      if (agentStatus != null)
        ...completer.agentStatusHooks(
          endpoint: agentStatus,
          memberId: member.id,
        ),
      if (delegateCommand != null)
        ...completer.delegateHooks(commands: [delegateCommand]),
      for (final hook in extensionHooks)
        ...completer.extensionHooks(
          extensionId: hook.extensionId,
          events: [hook.event],
          command: hook.command,
          matcher: hook.matcher,
        ),
      ...userHooks,
    ];
    final hookWriter = CliToolRegistry.builtIn()
        .capability<HookCapability>(CliTool.flashskyai);
    if (hookWriter != null && entries.isNotEmpty) {
      final hooksDir = delegate.joinWork(memberToolDir, 'hooks');
      final result = hookWriter.render(
        entries: entries,
        ctx: HookRenderContext(
          hooksDir: hooksDir,
          runner: delegate.hostEnvironmentForProvision().scriptRunner,
          glueBuilder: const GlueScriptBuilder(),
        ),
      );
      for (final script in result.scripts) {
        await delegate.fs.writeString(
          delegate.joinWork(hooksDir, script.fileName),
          script.content,
        );
      }
      settings = mergeHooksInto(
        settings,
        (result.configFragments['settings.json'] as Map<String, Object?>?) ??
            const <String, Object?>{},
      );
      for (final warning in result.warnings) {
        appLogger.d('[hook-writer] flashskyai $warning');
      }
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
      tools: const [FlashskyaiConfigProfileCapability.toolId],
    );
  }
}
