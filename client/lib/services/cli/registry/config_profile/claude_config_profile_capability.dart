import 'dart:convert';

import '../../../../models/claude_credential_link_result.dart';
import '../../../../models/personal_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../utils/team_member_naming.dart';
import '../../../provider/claude/claude_effort_capability.dart';
import '../../../provider/claude/claude_official_provider.dart';
import '../capabilities/cli_effort_capability.dart';
import '../../../provider/claude/claude_provider_credentials_service.dart';
import '../../../provider/credential_binding.dart';
import '../../../provider/cross_machine_credential_bridge.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../provider/claude/claude_provider_settings_resolver.dart';
import '../../../session/member_role_provision.dart';
import '../../../team/claude_team_roster_service.dart';
import '../capabilities/config_profile_capability.dart';
import '../../../provider/workspace_trust_provisioner.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import 'bus_idle_stop_hook.dart';
import '../../../../utils/logger.dart';

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
  const ClaudeConfigProfileCapability();

  static const toolId = 'claude';
  static const metadataFileName = '.claude.json';
  static const settingsFileEnvKey = 'TEAMPILOT_CLAUDE_SETTINGS_FILE';

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
  }) =>
      delegate.pathContext.join(
        delegate.sessionToolDir(
          workspaceId,
          sessionId,
          toolId,
          memberId: memberId,
        ),
        metadataFileName,
      );

  static String sessionMemberSettingsFile(
    ConfigProfileDelegate delegate,
    String workspaceId,
    String sessionId,
    TeamMemberConfig member, {
    String? memberId,
  }) =>
      delegate.pathContext.join(
        delegate.sessionToolDir(
          workspaceId,
          sessionId,
          toolId,
          memberId: memberId,
        ),
        'settings',
        '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
      );

  Future<ClaudeLaunchExtras> resolveLaunchExtras({
    required TeamProfile team,
    required TeamMemberConfig? member,
    required ClaudeProviderSettingsResolver resolver,
  }) async {
    final settings = await resolver.resolveTeamClaudeSettings(team);
    final providerId = await resolver.resolveProviderId(team);
    final settingsByMember = await _loadMemberProviderSettings(
      resolver: resolver,
      team: team,
      teamClaudeSettings: settings,
      launchedMember: member,
    );
    return ClaudeLaunchExtras(
      settings: settings,
      providerId: providerId,
      settingsByMember: settingsByMember,
    );
  }

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      await _ensureSessionDefaultsAt(
        ctx.paths,
        standaloneSessionToolDir(ctx.paths, standalone, toolId),
      );
      return;
    }
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
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      return _contributeStandaloneLaunch(ctx, standalone, personal);
    }

    final delegate = ctx.paths;
    final catalog = ctx.catalog;
    final scope = ctx.scope;
    final workingDirectory = ctx.workingDirectory ?? '';
    final team = ctx.team;
    final warnings = <String>[];
    final mixed = team?.teamMode == TeamMode.mixed;

    ClaudeLaunchExtras? claude;
    if (team != null) {
      final resolver = _claudeResolver(catalog);
      claude = await resolveLaunchExtras(
        team: team,
        member: ctx.member,
        resolver: resolver,
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
    final effortLevel = _resolveClaudeEffort(
      team: team,
      member: ctx.member,
      model: ctx.member?.model ?? '',
    );
    await _writeSettings(
      delegate,
      scope,
      claude?.settings,
      effortLevel: effortLevel,
      teammateMode: team?.claudeTeammateMode ?? 'in-process',
      mixed: mixed,
    );
    if (!mixed) {
      await _writeRoster(
        delegate: delegate,
        scope: scope,
        members: ctx.members,
        workingDirectory: workingDirectory,
        description: team?.description ?? '',
        leadSessionId: ctx.leadSessionId,
        teammateMode: team?.claudeTeammateMode ?? 'in-process',
      );
    }
    await _writeMemberProfiles(
      delegate: delegate,
      scope: scope,
      team: team,
      members: ctx.members,
      launchedMember: ctx.member,
      providerSettings: claude?.settings,
      providerSettingsByMember: claude?.settingsByMember ?? const {},
      forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
      mixed: mixed,
      busIdle: ctx.busIdle,
    );

    await _maybeLinkOfficialCredentials(
      delegate: delegate,
      catalog: catalog,
      crossMachine: ctx.crossMachine,
      scope: scope,
      claude: claude,
      launchedMember: ctx.member,
      warnings: warnings,
    );

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
      if (!mixed) 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS': '1',
      'CLAUDE_CODE_NO_FLICKER': '1',
      'MCP_TOOL_TIMEOUT': '$busToolTimeoutMs',
    };

    if (member != null && member.isValid) {
      final appendPath = await delegate.resolveAppendSystemPromptPath(
        scope: scope,
        tool: toolId,
        member: member,
      );
      if (appendPath != null) {
        environment[MemberRoleProvision.appendSystemPromptFileEnvKey] =
            appendPath;
      }
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
    final file = delegate.pathContext.join(memberToolDir, metadataFileName);
    final existing = await delegate.readMetadataFile(file, defaultMetadata);
    await delegate.writeJsonIfChanged(file, {
      ...defaultMetadata,
      ...existing,
    });
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
    PersonalProfile personal,
  ) async {
    final sessionId = standalone.sessionId;
    final stepSw = Stopwatch()..start();
    appLogger.d(
      '[session-lifecycle] contributeLaunch start session=$sessionId cli=claude',
    );

    final delegate = ctx.paths;
    final catalog = ctx.catalog;
    final member = standaloneMemberFromPersonal(personal, preset: ctx.preset);
    final memberToolDir = standaloneSessionToolDir(delegate, standalone, toolId);
    final scope = launchScopeForStandalone(standalone);
    final workingDirectory = ctx.workingDirectory ?? '';
    final warnings = <String>[];

    final resolver = _claudeResolver(catalog);
    final providerId = standaloneProviderId(ctx.preset);
    final settings = await resolver.resolve(
      providerId.isNotEmpty ? providerId : null,
    );
    final resolvedProviderId = providerId.isNotEmpty
        ? providerId
        : (settings != null
              ? (await _resolveSoleClaudeProviderId(catalog))
              : null);
    _logClaudeContributeLaunchStep(
      stepSw,
      'resolveProviderSettings',
      sessionId,
      extra: 'providerId=${resolvedProviderId ?? ''}',
    );

    await _provisionWorkspaceTrust(
      delegate: delegate,
      workspaceId: scope.workspaceId,
      workingDirectory: workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    _logClaudeContributeLaunchStep(stepSw, 'provisionWorkspaceTrust', sessionId);

    await _writeMetadataAt(
      delegate,
      memberToolDir,
      workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );
    _logClaudeContributeLaunchStep(stepSw, 'writeMetadata', sessionId);

    final effortLevel = _resolveClaudeEffort(
      team: null,
      member: member,
      model: ctx.preset?.model ?? member.model,
      profileEffort: ctx.preset?.effort ?? '',
    );
    await _writeSettingsAt(
      delegate,
      memberToolDir,
      scope,
      settings,
      effortLevel: effortLevel,
      standalone: true,
    );
    _logClaudeContributeLaunchStep(stepSw, 'writeSettings', sessionId);

    await _writeStandaloneMemberProfile(
      delegate: delegate,
      memberToolDir: memberToolDir,
      scope: scope,
      member: member,
      providerSettings: settings,
      team: null,
      effortLevel: effortLevel,
    );
    _logClaudeContributeLaunchStep(stepSw, 'writeStandaloneMemberProfile', sessionId);

    final trimmedProviderId = resolvedProviderId?.trim() ?? '';
    if (trimmedProviderId.isNotEmpty &&
        settings != null &&
        isOfficialClaudeSettings(settings)) {
      await _linkOfficialClaudeCredentials(
        delegate: delegate,
        catalog: catalog,
        crossMachine: ctx.crossMachine,
        sessionClaudeDir: memberToolDir,
        providerId: trimmedProviderId,
        warnings: warnings,
      );
      _logClaudeContributeLaunchStep(
        stepSw,
        'linkOfficialCredentials',
        sessionId,
        extra: 'warnings=${warnings.length}',
      );
    }

    final environment = <String, String>{
      'CLAUDE_CONFIG_DIR': memberToolDir,
      if (member.isValid)
        settingsFileEnvKey: delegate.pathContext.join(
          memberToolDir,
          'settings',
          '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
        ),
      'CLAUDE_CODE_NO_FLICKER': '1',
      'MCP_TOOL_TIMEOUT': '$busToolTimeoutMs',
    };

    if (member.isValid) {
      final appendPath = await delegate.resolveAppendSystemPromptPath(
        scope: scope,
        tool: toolId,
        member: member,
      );
      _logClaudeContributeLaunchStep(stepSw, 'resolveAppendSystemPrompt', sessionId);
      if (appendPath != null) {
        environment[MemberRoleProvision.appendSystemPromptFileEnvKey] =
            appendPath;
      }
    }

    stepSw.stop();
    appLogger.d(
      '[session-lifecycle] contributeLaunch done session=$sessionId cli=claude',
    );

    return ConfigProfileLaunchContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<String?> _resolveSoleClaudeProviderId(
    ConfigProfilePaths catalog,
  ) async {
    final providers = await providerCatalogRepository(
      catalog,
    ).loadProviders(CliTool.claude);
    if (providers.length == 1) return providers.first.id;
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
    final providerId = _credentialProviderId(claude, launchedMember);
    if (providerId.isEmpty) return;

    final settings = _credentialSettings(claude, launchedMember);
    if (settings == null || !isOfficialClaudeSettings(settings)) return;

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
      final copied = await CrossMachineCredentialBridge.materializeClaudeCredential(
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
  ) =>
      ClaudeProviderSettingsResolver(
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

  Future<void> _writeMetadataAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
    String workingDirectory, {
    List<String> additionalDirectories = const [],
  }) async {
    final metadataPath = delegate.pathContext.join(
      memberToolDir,
      metadataFileName,
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

  Future<void> _writeSettingsAt(
    ConfigProfileDelegate delegate,
    String memberToolDir,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    String teammateMode = 'in-process',
    bool mixed = false,
    bool standalone = false,
  }) async {
    final file = delegate.pathContext.join(memberToolDir, 'settings.json');
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
      standalone: standalone,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      teamId: standalone ? null : scope.teamId,
      workspaceId: standalone ? scope.teamId : null,
    );
    await _approveProviderApiKeyInMetadata(
      delegate,
      memberToolDir,
      providerSettings,
    );
  }

  Future<void> _writeStandaloneMemberProfile({
    required ConfigProfileDelegate delegate,
    required String memberToolDir,
    required LaunchProfileScope scope,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
    required TeamProfile? team,
    required String effortLevel,
  }) async {
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: false,
      mixed: false,
    );
    final file = delegate.pathContext.join(
      memberToolDir,
      'settings',
      '${ClaudeTeamRosterService.safeClaudePathSegment(member.id)}.json',
    );
    final settings = _memberSettings(
      providerSettings,
      member,
      effortLevel: effortLevel,
      mixed: false,
      standalone: true,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: memberToolDir,
      tool: toolId,
      workspaceId: scope.teamId,
    );
    await _approveProviderApiKeyInMetadata(
      delegate,
      memberToolDir,
      providerSettings,
    );
  }

  Future<void> _writeSettings(
    ConfigProfileDelegate delegate,
    LaunchProfileScope scope,
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
    required bool mixed,
  }) async {
    final file = delegate.pathContext.join(
      delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
      'settings.json',
    );
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: teammateMode,
      mixed: mixed,
    );
    await delegate.writeSettingsFile(
      file,
      settings,
      memberToolDir: delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
      tool: toolId,
      teamId: scope.teamId,
    );
    await _approveProviderApiKeyInMetadata(
      delegate,
      delegate.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        toolId,
        memberId: scope.memberId,
      ),
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
    final rosterDir = delegate.pathContext.join(
      claudeDir,
      'teams',
      ClaudeTeamRosterService.safeClaudePathSegment(scope.cliTeamName),
    );
    final rosterPath = delegate.pathContext.join(rosterDir, 'config.json');

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

  Future<void> _writeMemberProfiles({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required List<TeamMemberConfig> members,
    required TeamMemberConfig? launchedMember,
    required Map<String, Object?>? providerSettings,
    required Map<String, Map<String, Object?>> providerSettingsByMember,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    MemberBusIdleEndpoint? busIdle,
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

    for (final member in uniqueMembers.values) {
      await _writeMemberProfile(
        delegate: delegate,
        scope: scope,
        team: team,
        member: member,
        providerSettings:
            providerSettingsByMember[member.id] ?? providerSettings,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: mixed,
        busIdle: busIdle,
      );
    }
  }

  Future<void> _writeMemberProfile({
    required ConfigProfileDelegate delegate,
    required LaunchProfileScope scope,
    required TeamProfile? team,
    required TeamMemberConfig member,
    required Map<String, Object?>? providerSettings,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    MemberBusIdleEndpoint? busIdle,
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
    await MemberRoleProvision.syncRolePromptFile(
      fs: delegate.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && forceTeamLeadDelegateMode,
      mixed: mixed,
    );
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
      mixed: mixed,
    );
    settings = MemberRoleProvision.applyTeamSessionPolicy(settings, mixed: mixed);
    if (mixed && busIdle != null) {
      settings = mergeStopIdleHook(settings, member.id, busIdle);
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
      teamId: scope.teamId,
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
    required Map<String, Object?>? teamClaudeSettings,
    required TeamMemberConfig? launchedMember,
  }) async {
    final members = <String, TeamMemberConfig>{};
    for (final member in team.members.where((member) => member.isValid)) {
      members[member.id] = member;
    }
    final selected = launchedMember;
    if (selected != null && selected.isValid) {
      members[selected.id] = selected;
    }

    final settingsByMember = <String, Map<String, Object?>>{};
    for (final member in members.values) {
      final settings = await resolver.resolveMemberClaudeSettings(
        team: team,
        member: member,
        teamClaudeSettings: teamClaudeSettings,
      );
      if (settings != null) {
        settingsByMember[member.id] = settings;
      }
    }
    return settingsByMember;
  }

  static Map<String, Object?> _teamSettings(
    Map<String, Object?>? providerSettings, {
    required String effortLevel,
    required String teammateMode,
    required bool mixed,
    bool standalone = false,
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
    if (mixed || standalone) {
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
    if (mixed || standalone) {
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
      context: EffortResolveContext(
        team: team,
        member: member,
        model: model,
      ),
    );
  }

  static Map<String, Object?> _memberSettings(
    Map<String, Object?>? providerSettings,
    TeamMemberConfig member, {
    required String effortLevel,
    required bool mixed,
    bool standalone = false,
  }) {
    final settings = _teamSettings(
      providerSettings,
      effortLevel: effortLevel,
      teammateMode: 'in-process',
      mixed: mixed,
      standalone: standalone,
    );
    final model = member.model.trim();
    if (model.isNotEmpty) {
      final env = Map<String, Object?>.from(settings['env'] as Map);
      // The provider may pin a distinct background (haiku-tier) model; keep it
      // even when the member overrides the main model, so "big main + cheap
      // background" survives. Otherwise all tiers collapse to the member model.
      final providerMain =
          (env['ANTHROPIC_MODEL'] as String?)?.trim() ?? '';
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

    final metadataPath = delegate.pathContext.join(
      memberToolDir,
      metadataFileName,
    );
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
