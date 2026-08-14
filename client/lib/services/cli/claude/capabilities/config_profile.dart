import 'dart:convert';

import '../../../../models/credential_link_result.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/team_config.dart';
import '../../../../models/hook_entry.dart';
import '../../../../repositories/cli_presets_repository.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../provider/claude_effort_capability.dart';
import '../provider/claude_official_provider.dart';
import '../../registry/capabilities/cli_effort_capability.dart';
import '../provider/claude_provider_credentials_service.dart';
import '../../../provider/credential_binding.dart';
import '../../../launch/work_plane_paths.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/provider_catalog_access.dart';
import '../provider/claude_provider_settings_resolver.dart';
import '../../../session/member_role_provision.dart';
import '../team_roster_service.dart';
import '../../registry/capabilities/config_profile_capability.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import 'prompt_provision.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/capabilities/claude_family_hook_registry.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/cli_tool_registry.dart';
import '../../../../utils/logging/logger.dart';
import '../../../hook/glue_script_builder.dart';

void _logClaudeContributeLaunchStep(
  Stopwatch sw,
  String step,
  String sessionId, {
  String? extra,
}) {
  final elapsedMs = sw.elapsedMilliseconds;
  sw
    ..stop()
    ..reset()
    ..start();
  final suffix = extra == null ? '' : ' $extra';
  appLogger.d(
    '[session-lifecycle] contributeLaunch step=$step '
    'elapsedMs=$elapsedMs session=$sessionId cli=claude$suffix',
  );
}

class ClaudeLaunchExtras {
  const ClaudeLaunchExtras({
    this.settings,
    this.providerId,
    this.settingsByMember = const {},
  });

  final Map<String, Object?>? settings;
  final String? providerId;
  final Map<String, Map<String, Object?>> settingsByMember;
}

final class ClaudeConfigProfileCapability implements ConfigProfileCapability {
  const ClaudeConfigProfileCapability({
    this.promptProvision = const ClaudePromptProvisionCapability(),
  });

  static const toolId = 'claude';
  static const metadataFileName = '.claude.json';
  static const settingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

  final PromptProvisionCapability promptProvision;

  /// MCP 工具调用超时(毫秒)。team-bus 的 `wait_for_message` 是长阻塞工具,
  /// claude 默认的工具超时会在几分钟后掐断它(progress notification 不续命,
  /// 见 MCP SDK `resetTimeoutOnProgress` 默认 false)。设大到 24h 让 claude 不
  /// 主动超时,对齐 codex 的 `tool_timeout_sec`(那边单位是秒:86400)。
  static const busToolTimeoutMs = 86400000; // 24h，单位 ms

  static const defaultMetadata = <String, Object?>{
    'hasCompletedOnboarding': true,
    // Follow the embedded terminal's light/dark instead of Claude's built-in
    // 'dark' default, so a session is themed out of the box (no `/theme`). The
    // CLI resolves 'auto' from the COLORFGBG we inject at launch
    // (see PtyLaunchEnvironment.applyColorScheme). Seed-only: a later user
    // `/theme` choice is written to the file and wins via `{...defaults, ...existing}`.
    'theme': 'auto',
  };

  static const defaultProjectConfig = <String, Object?>{
    'hasTrustDialogAccepted': true,
    'hasCompletedProjectOnboarding': true,
    'projectOnboardingSeenCount': 1,
    'hasClaudeMdExternalIncludesApproved': true,
    'hasClaudeMdExternalIncludesWarningShown': true,
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

  static String sessionMemberSettingsFile(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId,
    TeamMemberConfig member, {
    String? memberId,
  }) => delegate.joinWork(
    delegate.sessionToolDir(workspaceId, sessionId, toolId, memberId: memberId),
    'settings',
    '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
  );

  Future<ClaudeLaunchExtras> resolveLaunchExtras({
    required TeamProfile team,
    required List<TeamMemberConfig> launchResolvedMembers,
    required TeamMemberConfig? launchedMember,
    required ClaudeProviderSettingsResolver resolver,
    List<CliPreset> globalPresets = const [],
  }) async {
    final normalized = team.normalizedLaunchConfig();
    final settings = await resolver.resolveTeamClaudeSettings(
      normalized,
      globalPresets: globalPresets,
    );
    final providerId = await resolver.resolveProviderId(
      normalized,
      globalPresets: globalPresets,
    );
    final settingsByMember = await _loadMemberProviderSettings(
      resolver: resolver,
      team: normalized,
      launchResolvedMembers: launchResolvedMembers,
      launchedMember: launchedMember,
      teamClaudeSettings: settings,
      globalPresets: globalPresets,
    );
    return ClaudeLaunchExtras(
      settings: settings,
      providerId: providerId,
      settingsByMember: settingsByMember,
    );
  }

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    await _ensureSessionDefaults(
      ctx.paths,
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
    final catalog = ctx.catalog;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final team = ctx.team;
    final simple = ctx.isSimple;
    final warnings = <String>[];
    final mixed = team?.teamMode == TeamMode.mixed;
    final sessionId = scope.sessionId;
    final stepSw = simple ? (Stopwatch()..start()) : null;
    if (simple) {
      appLogger.d(
        '[session-lifecycle] contributeLaunch start session=$sessionId cli=claude',
      );
    }

    ClaudeLaunchExtras? claude;
    if (team != null) {
      final resolver = _claudeResolver(catalog);
      final globalPresets = await _loadGlobalPresets(catalog);
      claude = await resolveLaunchExtras(
        team: team,
        launchResolvedMembers: ctx.members,
        launchedMember: ctx.member,
        resolver: resolver,
        globalPresets: globalPresets,
      );
      final launched = ctx.member;
      if (launched != null &&
          launched.isValid &&
          launched.provider.trim().isNotEmpty) {
        final memberSettings = claude.settingsByMember[launched.id];
        final env = memberSettings?['env'];
        final hasProviderEnv =
            env is Map &&
            env.keys.any((key) => key.toString().startsWith('ANTHROPIC_'));
        if (!hasProviderEnv) {
          warnings.add('claude_provider_missing:${launched.id}');
        }
      }
    } else if (simple) {
      final member =
          ctx.member ??
          (throw StateError('Simple launch requires plan.member'));
      final resolver = _claudeResolver(catalog);
      var providerId = member.provider.trim();
      // Expert packs / empty presets often omit provider. Without a fallback,
      // official OAuth credentials are never linked into CLAUDE_CONFIG_DIR and
      // resume shows the login screen.
      if (providerId.isEmpty) {
        providerId = (await _resolveDefaultClaudeProviderId(catalog)) ?? '';
      }
      final settings = await resolver.resolve(
        providerId.isNotEmpty ? providerId : null,
      );
      final resolvedProviderId = providerId.isNotEmpty ? providerId : null;
      if (stepSw != null) {
        _logClaudeContributeLaunchStep(
          stepSw,
          'resolveProviderSettings',
          sessionId,
          extra: 'providerId=${resolvedProviderId ?? ''}',
        );
      }
      claude = ClaudeLaunchExtras(
        settings: settings,
        providerId: resolvedProviderId,
        settingsByMember: settings == null ? const {} : {member.id: settings},
      );
    } else {
      claude = const ClaudeLaunchExtras();
    }

    await _provisionWorkspaceTrust(
      delegate: delegate,
      workspaceId: scope.workspaceId,
      workingDirectory: workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    if (stepSw != null) {
      _logClaudeContributeLaunchStep(
        stepSw,
        'provisionWorkspaceTrust',
        sessionId,
      );
    }
    await _writeMetadata(
      delegate,
      scope,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    if (stepSw != null) {
      _logClaudeContributeLaunchStep(stepSw, 'writeMetadata', sessionId);
    }
    final effortLevel = _resolveClaudeEffort(
      team: team,
      member: ctx.member,
      model: ctx.member?.model ?? '',
      profileEffort: ctx.member?.effort ?? '',
    );
    final teammateMode = resolveTeammateMode(
      team,
      mixed: mixed,
      simple: simple,
    );
    await _writeSettings(
      delegate,
      scope,
      claude.settings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
      simple: simple,
    );
    if (stepSw != null) {
      _logClaudeContributeLaunchStep(stepSw, 'writeSettings', sessionId);
    }
    if (!mixed && !simple) {
      await _writeRoster(
        delegate: delegate,
        scope: scope,
        members: ctx.members,
        workingDirectory: workingDirectory,
        description: team?.description ?? '',
        leadSessionId: ctx.leadSessionId,
        teammateMode: teammateMode,
      );
    }
    final appendPromptEnv = await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      team: team,
      members: ctx.members,
      launchedMember: ctx.member,
      providerSettings: claude.settings,
      providerSettingsByMember: claude.settingsByMember,
      forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
      mixed: mixed,
      simple: simple,
      busIdle: ctx.busIdle,
      agentStatus: ctx.agentStatus,
      userHooks: ctx.hooks,
    );
    if (stepSw != null) {
      _logClaudeContributeLaunchStep(stepSw, 'writeMemberProfiles', sessionId);
    }

    // Credential linking is best-effort — failures must not prevent the
    // environment from being built.  When the provider-level symlink already
    // exists (the common case when multiple members launch concurrently),
    // materializeLinkedBinding is a no-op thanks to the readSymlinkTarget guard.
    try {
      await _maybeLinkOfficialCredentials(
        delegate: delegate,
        catalog: catalog,
        crossMachine: ctx.crossMachine,
        scope: scope,
        claude: claude,
        launchedMember: ctx.member,
        warnings: warnings,
      );
    } on Object catch (e) {
      warnings.add('claude_credentials_link_error: $e');
    }
    if (stepSw != null) {
      _logClaudeContributeLaunchStep(
        stepSw,
        'linkOfficialCredentials',
        sessionId,
        extra: 'warnings=${warnings.length}',
      );
    }

    final member = ctx.member;
    final environment = <String, String>{
      'CLAUDE_CONFIG_DIR': delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
      if (member != null && member.isValid)
        settingsFileEnvKey: sessionMemberSettingsFile(
          delegate,
          scope.workspaceId,
          scope.sessionId,
          member,
          memberId: scope.memberId,
        ),
      if (!mixed && !simple) 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      'CLAUDE_CODE_NO_FLICKER': '1',
      'MCP_TOOL_TIMEOUT': '$busToolTimeoutMs',
    };

    environment.addAll(appendPromptEnv);

    if (stepSw != null) {
      stepSw.stop();
      appLogger.d(
        '[session-lifecycle] contributeLaunch done session=$sessionId cli=claude',
      );
    }

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

  /// Default Claude provider when Simple launch has none pinned.
  ///
  /// Prefer Anthropic official (`claude-official` / official category) so
  /// OAuth credentials can be linked; sole-provider fallback last.
  Future<String?> _resolveDefaultClaudeProviderId(
    ConfigProfilePaths catalog,
  ) async {
    final providers = await providerCatalogRepository(
      catalog,
    ).loadProviders(CliTool.claude);
    if (providers.isEmpty) return null;
    if (providers.length == 1) return providers.first.id;

    for (final provider in providers) {
      if (provider.id.trim() == 'claude-official') return provider.id;
    }
    for (final provider in providers) {
      if (isOfficialClaudeProvider(provider)) return provider.id;
    }
    return null;
  }

  Future<void> _maybeLinkOfficialCredentials({
    required ConfigProfileDelegate delegate,
    required ConfigProfilePaths catalog,
    required bool crossMachine,
    required LaunchProfileScope scope,
    required ClaudeLaunchExtras? claude,
    required TeamMemberConfig? launchedMember,
    required List<String> warnings,
  }) async {
    var providerId = _credentialProviderId(claude, launchedMember);
    if (providerId.isEmpty) {
      providerId = (await _resolveDefaultClaudeProviderId(catalog)) ?? '';
    }
    if (providerId.isEmpty) return;

    final settings = _credentialSettings(claude, launchedMember);
    // Null settings = no third-party env → official login still needs a link.
    if (settings != null && !isOfficialClaudeSettings(settings)) return;

    final sessionClaudeDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await _linkOfficialClaudeCredentials(
      delegate: delegate,
      catalog: catalog,
      crossMachine: crossMachine,
      sessionClaudeDir: sessionClaudeDir,
      providerId: providerId,
      warnings: warnings,
    );
  }

  Future<void> _linkOfficialClaudeCredentials({
    required ConfigProfileDelegate delegate,
    required ConfigProfilePaths catalog,
    required bool crossMachine,
    required String sessionClaudeDir,
    required String providerId,
    required List<String> warnings,
  }) async {
    final binding = await _resolveClaudeCredentialBinding(catalog, providerId);
    if (crossMachine) {
      final copied =
          await CrossMachineCredentialBridge.materializeClaudeCredential(
            catalog: catalog,
            work: delegate,
            providerId: providerId,
            binding: binding,
          );
      if (!copied) {
        warnings.add('claude_credentials_missing');
        return;
      }
    }

    final credentials = ClaudeProviderCredentialsService(
      fs: delegate.fs,
      basePath: delegate.basePath,
      resolveHomeDirectory: () => delegate.home,
    );
    final link = await credentials.ensureLinked(
      sessionClaudeDir,
      providerId,
      binding: crossMachine ? CredentialBindingKind.isolated : binding,
      homeDirectory: delegate.home,
    );
    if (link == CredentialLinkResult.missing) {
      warnings.add('claude_credentials_missing');
    }
  }

  static ClaudeProviderSettingsResolver _claudeResolver(
    ConfigProfilePaths catalog,
  ) => ClaudeProviderSettingsResolver(
    basePath: catalog.basePath,
    repository: providerCatalogRepository(catalog),
  );

  /// Official credential linking follows the launched member's provider in
  /// mixed teams (per-member presets), not only the team-level Claude binding.
  static String _credentialProviderId(
    ClaudeLaunchExtras? claude,
    TeamMemberConfig? launchedMember,
  ) {
    if (launchedMember != null && launchedMember.isValid) {
      final fromMember = launchedMember.provider.trim();
      if (fromMember.isNotEmpty) return fromMember;
    }
    return claude?.providerId?.trim() ?? '';
  }

  static Map<String, Object?>? _credentialSettings(
    ClaudeLaunchExtras? claude,
    TeamMemberConfig? launchedMember,
  ) {
    if (launchedMember != null && launchedMember.isValid) {
      return claude?.settingsByMember[launchedMember.id] ?? claude?.settings;
    }
    return claude?.settings;
  }

  Future<CredentialBindingKind> _resolveClaudeCredentialBinding(
    ConfigProfilePaths catalog,
    String providerId,
  ) async {
    final providers = await providerCatalogRepository(
      catalog,
    ).loadProviders(CliTool.claude);
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) return CredentialBindingKind.linked;
    return resolveCredentialBinding(provider);
  }

  Future<void> _writeSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
    required bool mixed,
    bool simple = false,
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final file = delegate.joinWork(memberToolDir, 'settings.json');
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
      simple: simple,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: simple ? null : scope.teamId,
      workspaceId: simple ? scope.workspaceId : null,
    );
    await _approveProviderApiKeyInMetadata(
      delegate,
      memberToolDir,
      providerSettings,
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
    final metadata = await delegate.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: defaultMetadata,
      defaultProjectConfig: defaultProjectConfig,
      directories: [workingDirectory, ...additionalDirectories],
    );
    await delegate.fs.atomicWrite(
      metadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<void> _writeRoster({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required List<TeamMemberConfig> members,
    required String workingDirectory,
    required String description,
    required String teammateMode,
    String? leadSessionId,
  }) async {
    final claudeDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final rosterDir = delegate.joinWork(
      claudeDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(scope.cliTeamName),
    );
    final rosterPath = delegate.joinWork(rosterDir, 'config.json');

    final cwd = ClaudeTeamRosterService.resolveWorkingDirectory(
      workingDirectory: workingDirectory,
      fallback: '',
    );

    Map<String, Object?>? existing;
    if ((await delegate.fs.stat(rosterPath)).exists) {
      final raw = await delegate.fs.readString(rosterPath);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          existing = Map<String, Object?>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    }

    final rosterService = ClaudeTeamRosterService(fs: delegate.fs);
    final config = rosterService.mergeConfig(
      cliTeamName: scope.cliTeamName,
      members: members,
      cwd: cwd,
      teammateMode: teammateMode,
      description: description,
      leadSessionId: leadSessionId,
      existing: existing,
    );

    await delegate.fs.atomicWrite(
      rosterPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
    await rosterService.ensureInboxes(rosterDir: rosterDir, members: members);
  }

  Future<Map<String, String>> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required Map<String, Object?>? providerSettings,
    required Map<String, Map<String, Object?>> providerSettingsByMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    bool simple = false,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    List<HookEntry> userHooks = const [],
  }) async {
    final selected = launchedMember;
    final uniqueMembers = <String, TeamMemberConfig>{};
    if (!mixed) {
      for (final member in members.where((member) => member.isValid)) {
        uniqueMembers[member.id] = member;
      }
    }
    if (selected != null && selected.isValid) {
      uniqueMembers[selected.id] = selected;
    }

    final appendPromptEnv = <String, String>{};
    for (final member in uniqueMembers.values) {
      await _writeMemberProfile(
        delegate: delegate,
        scope: scope,
        team: team,
        member: member,
        launchedMember: selected,
        appendPromptEnv: appendPromptEnv,
        providerSettings:
            providerSettingsByMember[member.id] ?? providerSettings,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: mixed,
        simple: simple,
        busIdle: busIdle,
        agentStatus: agentStatus,
        userHooks: userHooks,
      );
    }
    return appendPromptEnv;
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required TeamMemberConfig member,
    required TeamMemberConfig? launchedMember,
    required Map<String, String> appendPromptEnv,
    required Map<String, Object?>? providerSettings,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    bool simple = false,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    List<HookEntry> userHooks = const [],
  }) async {
    final memberToolDir = delegate.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
    );
    final isLead = TeamMemberNaming.isTeamLead(member);
    final promptContribution = await promptProvision.provision(
      PromptProvisionContext(
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
    final file = sessionMemberSettingsFile(
      delegate,
      scope.workspaceId,
      scope.sessionId,
      member,
      memberId: mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
    );
    final effortLevel = _resolveClaudeEffort(
      team: team,
      member: member,
      model: member.model,
    );
    var settings = _memberSettings(
      providerSettings,
      member,
      effortLevel: effortLevel,
      team: team,
      mixed: mixed,
      simple: simple,
    );
    settings = MemberRoleProvision.applyTeamSessionPolicy(
      settings,
      mixed: mixed,
    );
    // 收敛：内部托管 hook（agent-status / bus idle / team-lead delegate /
    // 扩展 settings-hook）经 HookSeatContextCompleter 组装为 HookEntry，
    // 与 userHooks 一起走统一 writer 渲染。
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
    // 优先级（mergeHooksInto 按 (event, url|command) 去重、保留首个）：
    // managed → delegate → extension → user。Task 18 收敛前 delegate 在
    // 链尾追加（maybeApplyTeamLeadHooks），扩展在写盘时前置——去重收敛后
    // delegate/extension 前置保持其"胜出"语义（旧链中两源命令互不碰撞，
    // 可观察行为不变；分析见 task-18-report.md）。
    final entries = <HookEntry>[
      if (mixed && busIdle != null)
        ...completer.busIdleHooks(idle: busIdle, memberId: member.id),
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
    // Task 19：旧 CliHookSpec 资产注册路径已删除——managed 条目全部经上方
    // completer 组装，统一 writer 渲染（bus idle Stop 现带 timeout 5，不再被
    // 无 timeout 的 registry 资产 Stop 去重压掉）。
    final hookWriter = CliToolRegistry.builtIn().capability<HookCapability>(
      CliTool.claude,
    );
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
        appLogger.d('[hook-writer] claude $warning');
      }
    }
    settings = await delegate.maybeApplyTeamLeadHooks(
      settings,
      member,
      memberToolDir,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: simple ? null : scope.teamId,
      workspaceId: simple ? scope.workspaceId : null,
    );
    await _approveProviderApiKeyInMetadata(
      delegate,
      memberToolDir,
      providerSettings,
    );
  }

  Future<Map<String, Map<String, Object?>>> _loadMemberProviderSettings({
    required ClaudeProviderSettingsResolver resolver,
    required TeamProfile team,
    required List<TeamMemberConfig> launchResolvedMembers,
    TeamMemberConfig? launchedMember,
    required Map<String, Object?>? teamClaudeSettings,
    List<CliPreset> globalPresets = const [],
  }) async {
    final members = <String, TeamMemberConfig>{};
    for (final member in launchResolvedMembers) {
      if (!member.isValid) continue;
      members[member.id] = member;
    }
    // Mixed callers may pass only the launched seat via `member`; keep it in
    // the settings map so official OAuth linking does not fall back to the
    // team-level (possibly third-party) provider settings.
    if (launchedMember != null && launchedMember.isValid) {
      members[launchedMember.id] = launchedMember;
    }

    final settingsByMember = <String, Map<String, Object?>>{};
    for (final member in members.values) {
      final settings = await resolver.resolveMemberClaudeSettings(
        team: team,
        member: member,
        teamClaudeSettings: teamClaudeSettings,
        globalPresets: globalPresets,
      );
      if (settings != null) {
        settingsByMember[member.id] = settings;
      }
    }
    return settingsByMember;
  }

  Future<List<CliPreset>> _loadGlobalPresets(ConfigProfilePaths catalog) async {
    final presetsPath = catalog.pathContext.join(
      catalog.basePath,
      'cli-presets.json',
    );
    return CliPresetsRepository(
      fs: catalog.fs,
      presetsPath: presetsPath,
    ).load();
  }

  static Map<String, Object?> _teamSettings(
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
    required bool mixed,
    bool simple = false,
  }) {
    final settings = <String, Object?>{
      if (providerSettings != null) ...providerSettings,
    };
    final env = <String, Object?>{};
    final existingEnv = settings['env'];
    if (existingEnv is Map) {
      for (final entry in existingEnv.entries) {
        final key = entry.key;
        if (key is String) {
          env[key] = entry.value;
        }
      }
    }
    if (mixed || simple) {
      env.remove('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS');
    } else {
      env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1';
    }
    env['CLAUDE_CODE_NO_FLICKER'] = '1';
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    settings['env'] = env;
    settings['effortLevel'] = effortLevel;
    settings['skipDangerousModePermissionPrompt'] = true;
    if (mixed || simple) {
      settings.remove('teammateMode');
    } else {
      settings['teammateMode'] = teammateMode;
    }
    return settings;
  }

  static String _resolveClaudeEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required String model,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = ClaudeEffortCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.claude,
      context: EffortResolveContext(team: team, member: member, model: model),
    );
  }

  /// TeamPilot launches one Claude PTY per roster pod. `in-process` tells the
  /// lead to spawn teammates inside its own process instead of inbox dispatch
  /// to the external `developer-0` shells.
  static String resolveTeammateMode(
    TeamProfile? team, {
    required bool mixed,
    required bool simple,
  }) {
    if (mixed || simple) {
      return team?.claudeTeammateMode ?? 'in-process';
    }
    final configured = team?.claudeTeammateMode ?? 'in-process';
    // TeamPilot launches one external PTY per pod. `in-process` / `tmux` route
    // SendMessage through pane backends that do not exist here; `auto` falls
    // back to TeammateMailbox (`inboxes/<pod>.json`) for external teammates.
    if (configured == 'in-process') return 'auto';
    return configured;
  }

  static Map<String, Object?> _memberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member, {
    required String effortLevel,
    TeamProfile? team,
    required bool mixed,
    bool simple = false,
  }) {
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: resolveTeammateMode(team, mixed: mixed, simple: simple),
      mixed: mixed,
      simple: simple,
    );
    final model = member.model.trim();
    if (model.isNotEmpty) {
      final env = Map<String, Object?>.from(settings['env'] as Map);
      // The provider may pin a distinct background (haiku-tier) model; keep it
      // even when the member overrides the main model, so "big main + cheap
      // background" survives. Otherwise all tiers collapse to the member model.
      final providerMain = (env['ANTHROPIC_MODEL'] as String?)?.trim() ?? '';
      final providerHaiku =
          (env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] as String?)?.trim() ?? '';
      final background =
          (providerHaiku.isNotEmpty && providerHaiku != providerMain)
          ? providerHaiku
          : model;
      env['ANTHROPIC_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = background;
      settings['env'] = env;
    }
    return settings;
  }

  /// Matches Claude Code `normalizeApiKeyForConfig` (last 20 chars).
  static String normalizeCustomApiKeySuffix(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 20) return trimmed;
    return trimmed.substring(trimmed.length - 20);
  }

  static Map<String, Object?> mergeApprovedCustomApiKeyMetadata(
    Map<String, Object?> metadata,
    String apiKey,
  ) {
    final suffix = normalizeCustomApiKeySuffix(apiKey);
    if (suffix.isEmpty) return metadata;

    final responses = Map<String, Object?>.from(
      (metadata['customApiKeyResponses'] as Map?)?.cast<String, Object?>() ??
          const {},
    );
    final approved = List<Object?>.from(
      (responses['approved'] as List?) ?? const <Object?>[],
    );
    if (!approved.contains(suffix)) {
      approved.add(suffix);
    }
    responses['approved'] = approved;
    responses.putIfAbsent('rejected', () => <Object?>[]);

    return {...metadata, 'customApiKeyResponses': responses};
  }

  static String _apiKeyFromClaudeProviderSettings(
    Map<String, Object?>? providerSettings,
  ) {
    if (providerSettings == null) return '';
    final env = providerSettings['env'];
    if (env is! Map) return '';
    for (final key in ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN']) {
      final value = env[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Pre-approves third-party provider keys so Claude Code skips the
  /// "Detected a custom API key" interactive gate at first launch.
  Future<void> _approveProviderApiKeyInMetadata(
    ConfigProfileDelegate delegate,
    String memberToolDir,
    Map<String, Object?>? providerSettings,
  ) async {
    final apiKey = _apiKeyFromClaudeProviderSettings(providerSettings);
    if (apiKey.isEmpty) return;

    final metadataPath = delegate.joinWork(memberToolDir, metadataFileName);
    final existing = await delegate.readMetadataFile(
      metadataPath,
      defaultMetadata,
    );
    final merged = mergeApprovedCustomApiKeyMetadata(existing, apiKey);
    await delegate.writeJsonIfChanged(metadataPath, merged);
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
      tools: const [ClaudeConfigProfileCapability.toolId],
    );
  }
}
